#!/usr/bin/env bash
set -euo pipefail

N="${1:-10}"

for i in $(seq -w 1 "${N}"); do
  RUN_ID="classic_${i}"
  echo "========================================"
  echo "[*] Ejecutando ${RUN_ID}"
  echo "========================================"

  ./scripts/run_classic_once.sh "${RUN_ID}"
  ./scripts/extract_metrics.sh "${RUN_ID}"

  sleep 2
done

echo "[*] Batch completado"
