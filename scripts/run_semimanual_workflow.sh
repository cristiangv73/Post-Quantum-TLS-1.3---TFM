#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:?Uso: ./scripts/run_semimanual_workflow.sh classic_001}"
SERVER_IP="${2:-192.168.0.10}"
SERVER_PORT="${3:-4433}"
MONITOR_PCAP_DIR="${4:-/tmp/captures}"

echo "========================================"
echo "[*] Flujo semimanual para ${RUN_ID}"
echo "========================================"
echo
echo "[1] Asegúrate de haber arrancado la captura en el monitor:"
echo "    docker exec -it pqc_monitor bash -lc 'mkdir -p ${MONITOR_PCAP_DIR} && dumpcap -i eth0 -w ${MONITOR_PCAP_DIR}/${RUN_ID}.pcap'"
echo
echo "[2] Cuando dumpcap esté capturando, pulsa ENTER para lanzar el cliente."
read -r

./scripts/run_client_once.sh "${RUN_ID}" "${SERVER_IP}" "${SERVER_PORT}"

echo
echo "[3] Para ahora la captura manualmente con Ctrl+C en la terminal del monitor."
echo "    Cuando ya la hayas parado, pulsa ENTER para copiar el pcap."
read -r

./scripts/fetch_pcap.sh "${RUN_ID}" "${MONITOR_PCAP_DIR}"
./scripts/extract_metrics.sh "${RUN_ID}"

echo
echo "[*] Flujo completado para ${RUN_ID}"
echo "    - pcap:    pcaps/${RUN_ID}.pcap"
echo "    - tiempo:  results/${RUN_ID}_time.txt"
echo "    - cliente: results/${RUN_ID}_client.txt"
echo "    - métricas: results/${RUN_ID}_metrics.txt"
