#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$(pwd)/docs/certs/out}"
mkdir -p "${OUT_DIR}"

# 1) CA for server certificate (ingress server identity)
openssl genrsa -out "${OUT_DIR}/server-ca.key" 4096
openssl req -x509 -new -nodes -key "${OUT_DIR}/server-ca.key" -sha256 -days 365 \
  -subj "/CN=local-server-ca/O=istio-workshop" \
  -out "${OUT_DIR}/server-ca.crt"

# 2) Server cert for example.com (presented by Istio ingress gateway)
openssl genrsa -out "${OUT_DIR}/server.key" 2048
openssl req -new -key "${OUT_DIR}/server.key" \
  -subj "/CN=example.com/O=istio-workshop" \
  -out "${OUT_DIR}/server.csr"

cat > "${OUT_DIR}/server-ext.cnf" <<EOT
subjectAltName=DNS:example.com,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
EOT

openssl x509 -req -in "${OUT_DIR}/server.csr" \
  -CA "${OUT_DIR}/server-ca.crt" -CAkey "${OUT_DIR}/server-ca.key" -CAcreateserial \
  -out "${OUT_DIR}/server.crt" -days 365 -sha256 \
  -extfile "${OUT_DIR}/server-ext.cnf"

# 3) Separate CA for client certs (used only when Gateway tls.mode=MUTUAL)
openssl genrsa -out "${OUT_DIR}/client-ca.key" 4096
openssl req -x509 -new -nodes -key "${OUT_DIR}/client-ca.key" -sha256 -days 365 \
  -subj "/CN=local-client-ca/O=istio-workshop" \
  -out "${OUT_DIR}/client-ca.crt"

# 4) Client cert presented by north-south client to ingress gateway
openssl genrsa -out "${OUT_DIR}/client.key" 2048
openssl req -new -key "${OUT_DIR}/client.key" \
  -subj "/CN=demo-client/O=istio-workshop" \
  -out "${OUT_DIR}/client.csr"

cat > "${OUT_DIR}/client-ext.cnf" <<EOT
extendedKeyUsage=clientAuth
EOT

openssl x509 -req -in "${OUT_DIR}/client.csr" \
  -CA "${OUT_DIR}/client-ca.crt" -CAkey "${OUT_DIR}/client-ca.key" -CAcreateserial \
  -out "${OUT_DIR}/client.crt" -days 365 -sha256 \
  -extfile "${OUT_DIR}/client-ext.cnf"

echo "Certificates created in ${OUT_DIR}"
echo "- server cert/key:   server.crt, server.key"
echo "- server CA cert:    server-ca.crt"
echo "- client cert/key:   client.crt, client.key"
echo "- client CA cert:    client-ca.crt"
