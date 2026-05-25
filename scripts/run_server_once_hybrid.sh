#!/usr/bin/env bash
set -x

RUN_ID="${1:-hybrid_001}"

mkdir -p results
rm -f "results/${RUN_ID}_server.txt" "results/${RUN_ID}_server_err.txt"

docker exec pqc_server sh -lc '
openssl s_server \
  -accept 4433 \
  -cert /certs/server/server.crt \
  -key /certs/server/server.key \
  -CAfile /certs/ca/ca.crt \
  -tls1_3 \
  -groups X25519MLKEM768 \
  -provider default \
  -provider oqsprovider \
  -www \
  > /results/'"${RUN_ID}"'_server.txt \
  2> /results/'"${RUN_ID}"'_server_err.txt
' || true

echo "=== host results ==="
ls -l results | grep "${RUN_ID}" || true
echo "=== stderr ==="
sed -n "1,80p" "results/${RUN_ID}_server_err.txt" || true
echo "=== stdout ==="
sed -n "1,80p" "results/${RUN_ID}_server.txt" || true
