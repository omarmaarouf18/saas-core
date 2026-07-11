#!/usr/bin/env bash
set -euo pipefail

# Determine script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Generating Local Root CA..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=SaaS-Platform-Local-Root-CA"

SERVICES=("api-gateway" "auth-service" "chat-service" "notification-service" "user-service")

for service in "${SERVICES[@]}"; do
  echo "Generating certificate for service: $service..."
  # Private Key
  openssl genrsa -out "${service}.key" 2048
  
  # CSR (Certificate Signing Request)
  openssl req -new -key "${service}.key" -out "${service}.csr" \
    -subj "/CN=${service}" \
    -addext "subjectAltName = DNS:${service}, DNS:localhost, IP:127.0.0.1"

  # Sign with CA (using extensions file)
  cat <<EOF > "${service}.ext"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:${service}, DNS:localhost, IP:127.0.0.1
EOF

  openssl x509 -req -in "${service}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out "${service}.crt" -days 3650 -sha256 -extfile "${service}.ext"

  # Clean up temp files
  rm -f "${service}.csr" "${service}.ext"
done

# Set permissions
chmod 600 *.key
chmod 644 *.crt

echo "Certificates generated successfully in $DIR!"
