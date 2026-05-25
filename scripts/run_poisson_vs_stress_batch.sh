#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/run_poisson_vs_stress_batch.sh [PREFIX] [TOTAL_CONN]

Variables opcionales:
  REPEATS=5                 # corridas por perfil
  INTERVAL_S=0.2            # intervalo docker stats
  SLEEP_AFTER=3             # sleep final dentro del comando medido
  CLIENTS="pqc_client,..." # lista explícita de clientes
  POISSON_RATE=25
  JITTER_MS=50
  EXTRACT_METRICS=0         # 1 para intentar extract_metrics2.sh por corrida
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

PREFIX="${1:-classic_cmp}"
TOTAL_CONN="${2:-1000}"
REPEATS="${REPEATS:-5}"
INTERVAL_S="${INTERVAL_S:-0.2}"
SLEEP_AFTER="${SLEEP_AFTER:-3}"
POISSON_RATE="${POISSON_RATE:-25}"
JITTER_MS="${JITTER_MS:-50}"
EXTRACT_METRICS="${EXTRACT_METRICS:-0}"

mkdir -p results
SUMMARY_CSV="results/${PREFIX}_poisson_vs_stress_summary.csv"

if [ -z "${CLIENTS:-}" ]; then
  CLIENTS="$(docker ps --format '{{.Names}}' | awk '/^pqc_client(_[0-9]+)?$/ {print $0}' | sort -V | paste -sd, -)"
fi

if [ -z "$CLIENTS" ]; then
  echo "[!] No se detectaron clientes. Define CLIENTS manualmente."
  exit 1
fi

echo "run_id,profile,iteration,total_conn,poisson_rate,jitter_ms,clients,pqc_client_cpu_avg,pqc_client_cpu_max,pqc_client_mem_avg,pqc_client_mem_max,pqc_server_cpu_avg,pqc_server_cpu_max,pqc_server_mem_avg,pqc_server_mem_max,pqc_monitor_cpu_avg,pqc_monitor_cpu_max,pqc_monitor_mem_avg,pqc_monitor_mem_max" > "$SUMMARY_CSV"

metric_from_summary() {
  local run_id="$1"
  local pattern="$2"
  local key="$3"
  local f="results/${run_id}_resource_summary.txt"
  [ -f "$f" ] || { echo "NA"; return; }
  awk -v p="$pattern" -v k="$key" '
    $0 ~ p {
      if (k=="cpu_avg" && match($0,/CPU avg=([0-9.]+)%/,m)) {print m[1]; found=1}
      else if (k=="cpu_max" && match($0,/CPU max=([0-9.]+)%/,m)) {print m[1]; found=1}
      else if (k=="mem_avg" && match($0,/MEM avg=([0-9.]+)%/,m)) {print m[1]; found=1}
      else if (k=="mem_max" && match($0,/MEM max=([0-9.]+)%/,m)) {print m[1]; found=1}
    }
    END { if (!found) print "NA" }
  ' "$f" | head -n 1
}

run_one() {
  local profile="$1"
  local iter="$2"
  local run_id="${PREFIX}_${profile}_$(printf '%03d' "$iter")"
  echo "[*] Ejecutando ${run_id} (profile=${profile})"

  CLIENTS="$CLIENTS" ARRIVAL_PROFILE="$profile" POISSON_RATE="$POISSON_RATE" JITTER_MS="$JITTER_MS" \
    ./scripts/measure_tls_resources.sh "$run_id" "$INTERVAL_S" -- \
    bash -lc "./scripts/run_client_once_rafaga.sh ${run_id} ${TOTAL_CONN}; sleep ${SLEEP_AFTER}"

  if [ "$EXTRACT_METRICS" = "1" ]; then
    ./scripts/extract_metrics2.sh "$run_id" || true
  fi

  local ccavg ccmax cmavg cmmax scavg scmax smavg smmax mcavg mcmax mmavg mmmax
  ccavg="$(metric_from_summary "$run_id" '^pqc_client(_[0-9]+)? ->' cpu_avg)"
  ccmax="$(metric_from_summary "$run_id" '^pqc_client(_[0-9]+)? ->' cpu_max)"
  cmavg="$(metric_from_summary "$run_id" '^pqc_client(_[0-9]+)? ->' mem_avg)"
  cmmax="$(metric_from_summary "$run_id" '^pqc_client(_[0-9]+)? ->' mem_max)"
  scavg="$(metric_from_summary "$run_id" '^pqc_server ->' cpu_avg)"
  scmax="$(metric_from_summary "$run_id" '^pqc_server ->' cpu_max)"
  smavg="$(metric_from_summary "$run_id" '^pqc_server ->' mem_avg)"
  smmax="$(metric_from_summary "$run_id" '^pqc_server ->' mem_max)"
  mcavg="$(metric_from_summary "$run_id" '^pqc_monitor ->' cpu_avg)"
  mcmax="$(metric_from_summary "$run_id" '^pqc_monitor ->' cpu_max)"
  mmavg="$(metric_from_summary "$run_id" '^pqc_monitor ->' mem_avg)"
  mmmax="$(metric_from_summary "$run_id" '^pqc_monitor ->' mem_max)"

  echo "${run_id},${profile},${iter},${TOTAL_CONN},${POISSON_RATE},${JITTER_MS},\"${CLIENTS}\",${ccavg},${ccmax},${cmavg},${cmmax},${scavg},${scmax},${smavg},${smmax},${mcavg},${mcmax},${mmavg},${mmmax}" >> "$SUMMARY_CSV"
}

for i in $(seq 1 "$REPEATS"); do run_one poisson_jitter "$i"; done
for i in $(seq 1 "$REPEATS"); do run_one stress "$i"; done

echo "[*] Batch completado. Resumen: $SUMMARY_CSV"
