#!/usr/bin/env bash
set -euo pipefail

mkdir -p certs/ca certs/server

openssl genpkey -algorithm RSA -out certs/ca/ca.key -pkeyopt rsa_keygen_bits:2048
openssl req -x509 -new -key certs/ca/ca.key -sha256 -days 365 \
  -out certs/ca/ca.crt \
  -subj "/C=ES/ST=Madrid/L=Madrid/O=TFM-PQC/OU=Lab/CN=TFM-PQC-CA"

openssl genpkey -algorithm RSA -out certs/server/server.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key certs/server/server.key \
  -out certs/server/server.csr \
  -subj "/C=ES/ST=Madrid/L=Madrid/O=TFM-PQC/OU=Server/CN=server"

cat > certs/server/server.ext <<EOF
subjectAltName=DNS:server,IP:172.28.0.10
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF

openssl x509 -req -in certs/server/server.csr \
  -CA certs/ca/ca.crt -CAkey certs/ca/ca.key -CAcreateserial \
  -out certs/server/server.crt -days 365 -sha256 \
  -extfile certs/server/server.ext

echo "Certificados generados correctamente."
