#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:?Uso: ./scripts/fetch_pcap.sh classic_001}"
MONITOR_PCAP_DIR="${2:-/tmp/captures}"

mkdir -p pcaps

SRC="pqc_monitor:${MONITOR_PCAP_DIR}/${RUN_ID}.pcap"
DST="pcaps/${RUN_ID}.pcap"

rm -f "${DST}"

echo "[*] Copiando ${SRC} -> ${DST}"
docker cp "${SRC}" "${DST}"

ls -lh "${DST}"
