#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/client_utils.sh
source "${SCRIPT_DIR}/client_utils.sh"

RUN_ID="${1:-classic_001}"
SERVER_IP="${2:-192.168.0.10}"
SERVER_PORT="${3:-4433}"
TARGET_CLIENT="${4:-$(first_resolved_client)}"

if [ -z "${TARGET_CLIENT}" ]; then
  echo "[!] No se encontró contenedor cliente"
  exit 1
fi

mkdir -p results
rm -f "results/${RUN_ID}_client.txt" "results/${RUN_ID}_client_err.txt"

docker exec "${TARGET_CLIENT}" sh -lc '
openssl s_client \
  -connect '"${SERVER_IP}:${SERVER_PORT}"' \
  -CAfile /certs/ca/ca.crt \
  -tls1_3 \
  -groups X25519 \
  < /dev/null \
  > /results/'"${RUN_ID}"'_client.txt \
  2> /results/'"${RUN_ID}"'_client_err.txt
' || true

if [ "${TARGET_CLIENT}" != "pqc_client" ]; then
  cp -f "results/${RUN_ID}_client.txt" "results/${RUN_ID}_${TARGET_CLIENT}_client.txt" || true
  cp -f "results/${RUN_ID}_client_err.txt" "results/${RUN_ID}_${TARGET_CLIENT}_client_err.txt" || true
fi

echo "[*] Cliente usado: ${TARGET_CLIENT}"
echo "=== host results ==="
ls -l results | grep "${RUN_ID}" || true
echo "=== stderr ==="
sed -n "1,80p" "results/${RUN_ID}_client_err.txt" || true
echo "=== stdout ==="
sed -n "1,80p" "results/${RUN_ID}_client.txt" || true
