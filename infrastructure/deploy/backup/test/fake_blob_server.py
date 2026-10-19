"""Minimal stand-in for Azure Blob Storage "Put Blob" (OPS-BACKUP tests only).

    python3 -I fake_blob_server.py <root dir> <port file> <file holding the expected sig>

Listens on 127.0.0.1 (random port, written to <port file>). Accepts
PUT /<container>/<blob path>?<SAS> and stores the body under <root dir>.
Like a create-only SAS on Azure it answers:
  201  stored
  400  missing/wrong x-ms-blob-type header
  403  wrong or missing sig= (AuthenticationFailed)
  409  blob already exists (BlobAlreadyExists)
Everything else is 405. One log line per request to stdout, without the
query string (the SAS never appears in the log).
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit

ROOT, PORT_FILE = sys.argv[1], sys.argv[2]
# Read from a file, not argv: the e2e test checks that no command line shows it.
with open(sys.argv[3]) as f:
    EXPECTED_SIG = f.read().strip()


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, azure_code=""):
        body = b""
        if azure_code:
            body = f"<?xml version=\"1.0\"?><Error><Code>{azure_code}</Code></Error>".encode()
        self.send_response(code)
        if azure_code:
            self.send_header("x-ms-error-code", azure_code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        path = urlsplit(self.path).path
        print(f"{self.command} {path} -> {code} {azure_code}".rstrip(), flush=True)

    def log_message(self, *args):  # silence the default log (it prints the query)
        pass

    def do_PUT(self):
        parts = urlsplit(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        sig = parse_qs(parts.query).get("sig", [""])[0]
        if sig != EXPECTED_SIG:
            return self._reply(403, "AuthenticationFailed")
        if self.headers.get("x-ms-blob-type") != "BlockBlob":
            return self._reply(400, "MissingRequiredHeader")
        rel = unquote(parts.path).lstrip("/")
        dest = os.path.realpath(os.path.join(ROOT, rel))
        if not dest.startswith(os.path.realpath(ROOT) + os.sep):
            return self._reply(400, "InvalidUri")
        if os.path.exists(dest):
            return self._reply(409, "BlobAlreadyExists")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)
        return self._reply(201)

    def _not_allowed(self):
        return self._reply(405, "UnsupportedHttpVerb")

    do_GET = do_DELETE = do_POST = do_HEAD = _not_allowed


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
