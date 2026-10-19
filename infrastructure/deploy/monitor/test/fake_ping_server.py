"""Minimal stand-in for a healthchecks.io ping endpoint (OBS-MIN local tests only).

    python3 -I fake_ping_server.py <log file> <port file>

Listens on 127.0.0.1 (random port, written to <port file>). Accepts GET or
POST on any path, answers 200 "OK" like healthchecks.io, and logs one line
per ping to <log file>:

    PING <path> <truncated body or "->">

(the log keeps neither the query string — not part of a ping URL — nor a
full body: test callers grep the log for ping order and body content).
"""

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

LOG_FILE, PORT_FILE = sys.argv[1], sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = ""
        if length:
            body = self.rfile.read(length).decode("utf-8", "replace")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"OK")
        path = unquote(urlsplit(self.path).path)
        body_line = body.replace("\r", " ").replace("\n", " ")[:300]
        with open(LOG_FILE, "a") as f:
            f.write(f"PING {path} {body_line}\n")

    def log_message(self, *args):  # silence the default log (it prints the path again)
        pass

    do_GET = _handle
    do_POST = _handle
    do_HEAD = _handle


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
