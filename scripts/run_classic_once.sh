#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:-classic_001}"
SERVER_IP="${2:-192.168.0.10}"
SERVER_PORT="${3:-4433}"
CLIENT_CONTAINER="${4:-pqc_client}"

HOST_PCAP_DIR="pcaps"
HOST_RESULTS_DIR="results"
MONITOR_CAPTURE_DIR="/tmp/captures"
MONITOR_PCAP_FILE="${MONITOR_CAPTURE_DIR}/${RUN_ID}.pcap"

mkdir -p "${HOST_PCAP_DIR}" "${HOST_RESULTS_DIR}"

PCAP_HOST="${HOST_PCAP_DIR}/${RUN_ID}.pcap"
CLIENT_OUT_HOST="${HOST_RESULTS_DIR}/${RUN_ID}_client.txt"
CLIENT_ERR_HOST="${HOST_RESULTS_DIR}/${RUN_ID}_client_err.txt"
TIME_HOST="${HOST_RESULTS_DIR}/${RUN_ID}_time.txt"
DUMPCAP_LOG="${HOST_RESULTS_DIR}/${RUN_ID}_dumpcap.log"

echo "[*] Run ID: ${RUN_ID}"

rm -f "${PCAP_HOST}" "${CLIENT_OUT_HOST}" "${CLIENT_ERR_HOST}" "${TIME_HOST}" "${DUMPCAP_LOG}"

echo "[*] Preparando captura en monitor..."
docker exec -u 0 pqc_monitor sh -lc "mkdir -p ${MONITOR_CAPTURE_DIR} && rm -f ${MONITOR_PCAP_FILE}"

echo "[*] Iniciando dumpcap..."
docker exec -u 0 pqc_monitor sh -lc \
  "dumpcap -i eth0 -w ${MONITOR_PCAP_FILE}" \
  > "${DUMPCAP_LOG}" 2>&1 &
CAP_PID=$!

sleep 2

echo "[*] Ejecutando handshake desde cliente (${CLIENT_CONTAINER})..."
docker exec -u 0 "${CLIENT_CONTAINER}" sh -lc "
  /usr/bin/time -f 'real=%e user=%U sys=%S' \
  openssl s_client \
    -connect ${SERVER_IP}:${SERVER_PORT} \
    -CAfile /certs/ca/ca.crt \
    -tls1_3 \
    -groups X25519 \
    < /dev/null \
    > /results/${RUN_ID}_client.txt \
    2> /results/${RUN_ID}_client_err.txt
" || true

sleep 2

echo "[*] Parando dumpcap..."
kill -INT "${CAP_PID}" || true
wait "${CAP_PID}" || true

echo "[*] Copiando pcap al host..."
docker cp "pqc_monitor:${MONITOR_PCAP_FILE}" "${PCAP_HOST}"

echo "[*] Extrayendo tiempo..."
grep '^real=' "${CLIENT_ERR_HOST}" > "${TIME_HOST}" || true

echo "[*] Resultado:"
ls -lh "${PCAP_HOST}"
