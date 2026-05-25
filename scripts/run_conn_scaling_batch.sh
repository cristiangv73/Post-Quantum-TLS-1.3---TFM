#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/run_conn_scaling_batch.sh [PREFIX]

Variables opcionales:
  CLIENTS="pqc_client,..."             # si no se define, autodetecta
  TOTAL_CONN_SET="300 600 1002 1500"   # múltiplos de nº de clientes recomendados
  REPEATS=5
  INTERVAL_S=0.2
  SLEEP_AFTER=3
  PROFILE_SET="balanced stress"         # valores: balanced stress
  POISSON_RATE_BALANCED=25
  JITTER_MS_BALANCED=50
  EXTRACT_METRICS=1
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

PREFIX="${1:-connscale}"
TOTAL_CONN_SET="${TOTAL_CONN_SET:-300 600 1002 1500}"
REPEATS="${REPEATS:-5}"
INTERVAL_S="${INTERVAL_S:-0.2}"
SLEEP_AFTER="${SLEEP_AFTER:-3}"
PROFILE_SET="${PROFILE_SET:-balanced stress}"
POISSON_RATE_BALANCED="${POISSON_RATE_BALANCED:-25}"
JITTER_MS_BALANCED="${JITTER_MS_BALANCED:-50}"
EXTRACT_METRICS="${EXTRACT_METRICS:-1}"

if [[ -z "${CLIENTS:-}" ]]; then
  CLIENTS="$(docker ps --format '{{.Names}}' | awk '/^pqc_client(_[0-9]+)?$/ {print $0}' | sort -V | paste -sd, -)"
fi

if [[ -z "$CLIENTS" ]]; then
  echo "[!] No se detectaron clientes. Define CLIENTS manualmente."
  exit 1
fi

mkdir -p results
SUMMARY="results/${PREFIX}_conn_scaling_summary.csv"

echo "run_id,mode,profile,total_conn,repeat,clients,poisson_rate,jitter_ms,pqc_client_cpu_avg,pqc_client_cpu_max,pqc_client_mem_avg,pqc_client_mem_max,pqc_server_cpu_avg,pqc_server_cpu_max,pqc_server_mem_avg,pqc_server_mem_max,pqc_monitor_cpu_avg,pqc_monitor_cpu_max,pqc_monitor_mem_avg,pqc_monitor_mem_max" > "$SUMMARY"

metric_from_summary() {
  local run_id="$1" pattern="$2" key="$3"
  local f="results/${run_id}_resource_summary.txt"
  [[ -f "$f" ]] || { echo "NA"; return; }
  awk -v p="$pattern" -v k="$key" '
    $0 ~ p {
      if (k=="cpu_avg" && match($0,/CPU avg=([0-9.]+)%/,m)) {print m[1]; ok=1}
      else if (k=="cpu_max" && match($0,/CPU max=([0-9.]+)%/,m)) {print m[1]; ok=1}
      else if (k=="mem_avg" && match($0,/MEM avg=([0-9.]+)%/,m)) {print m[1]; ok=1}
      else if (k=="mem_max" && match($0,/MEM max=([0-9.]+)%/,m)) {print m[1]; ok=1}
    }
    END { if (!ok) print "NA" }
  ' "$f" | head -n1
}

append_row() {
  local run_id="$1" mode="$2" profile="$3" total_conn="$4" rep="$5" pr="$6" jm="$7"
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

  echo "${run_id},${mode},${profile},${total_conn},${rep},\"${CLIENTS}\",${pr},${jm},${ccavg},${ccmax},${cmavg},${cmmax},${scavg},${scmax},${smavg},${smmax},${mcavg},${mcmax},${mmavg},${mmmax}" >> "$SUMMARY"
}

run_case() {
  local mode="$1" profile="$2" total_conn="$3" rep="$4"
  local rep3 run_id pr jm cmd
  rep3="$(printf '%03d' "$rep")"
  pr="NA"; jm="NA"

  if [[ "$profile" == "balanced" ]]; then
    pr="$POISSON_RATE_BALANCED"
    jm="$JITTER_MS_BALANCED"
  fi

  run_id="${PREFIX}_${mode}_${profile}_c${total_conn}_${rep3}"
  echo "[*] ${run_id}"

  if [[ "$mode" == "classic" ]]; then
    cmd="./scripts/run_client_once_rafaga.sh ${run_id} ${total_conn}; sleep ${SLEEP_AFTER}"
  else
    cmd="./scripts/run_client_once_rafaga_hibrido.sh ${run_id} ${total_conn}; sleep ${SLEEP_AFTER}"
  fi

  if [[ "$profile" == "balanced" ]]; then
    CLIENTS="$CLIENTS" ARRIVAL_PROFILE=poisson_jitter POISSON_RATE="$POISSON_RATE_BALANCED" JITTER_MS="$JITTER_MS_BALANCED" \
      ./scripts/measure_tls_resources.sh "$run_id" "$INTERVAL_S" -- bash -lc "$cmd"
  else
    CLIENTS="$CLIENTS" ARRIVAL_PROFILE=stress \
      ./scripts/measure_tls_resources.sh "$run_id" "$INTERVAL_S" -- bash -lc "$cmd"
  fi

  if [[ "$EXTRACT_METRICS" == "1" ]]; then
    ./scripts/extract_metrics2.sh "$run_id" || true
  fi

  append_row "$run_id" "$mode" "$profile" "$total_conn" "$rep" "$pr" "$jm"
}

for total in $TOTAL_CONN_SET; do
  for rep in $(seq 1 "$REPEATS"); do
    for mode in classic hybrid; do
      for profile in $PROFILE_SET; do
        run_case "$mode" "$profile" "$total" "$rep"
      done
    done
  done
done

echo "[*] Finalizado. Resumen: $SUMMARY"
