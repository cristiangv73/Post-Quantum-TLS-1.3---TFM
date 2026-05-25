#!/usr/bin/env bash
set -euo pipefail

CSV="results/classic_summary.csv"
echo "run_id,real_s,packets,bytes" > "${CSV}"

for f in results/classic_*_time.txt; do
  [ -e "$f" ] || continue

  RUN_ID=$(basename "$f" _time.txt)
  REAL=$(grep '^real=' "$f" | cut -d'=' -f2 | tr -d '[:space:]')

  PCAP="pcaps/${RUN_ID}.pcap"
  if [ ! -f "${PCAP}" ]; then
    continue
  fi

  PACKETS=$(capinfos "${PCAP}" | awk -F': ' '/Number of packets/ {print $2}' | tr -d ' ')
  BYTES=$(capinfos "${PCAP}" | awk -F': ' '/Data size/ {print $2}' | xargs)

  echo "${RUN_ID},${REAL},${PACKETS},${BYTES}" >> "${CSV}"
done

echo "[*] CSV generado en ${CSV}"
