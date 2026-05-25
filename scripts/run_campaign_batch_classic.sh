#!/usr/bin/env bash
set -euo pipefail

CLIENTS_DEFAULT="pqc_client,pqc_client_2,pqc_client_3,pqc_client_4,pqc_client_5,pqc_client_6"
CLIENTS="${CLIENTS:-$CLIENTS_DEFAULT}"

RUNS_PER_SCENARIO="${RUNS_PER_SCENARIO:-5}"
TOTAL_CONN="${TOTAL_CONN:-1002}"
TOTAL_CONN_VALUES="${TOTAL_CONN_VALUES:-$TOTAL_CONN}"
STATS_INTERVAL="${STATS_INTERVAL:-0.2}"

NET_PROFILES=(P0 P1 P2 P3)
ARRIVAL_SCENARIOS=(balanced aggressive soft stress)

MONITOR_CAPTURE_DIR="${MONITOR_CAPTURE_DIR:-/tmp/captures}"
MONITOR_IFACE="${MONITOR_IFACE:-eth0}"

RUN_IDS=()

ts() { date +"%Y-%m-%d %H:%M:%S"; }

poisson_rate() {
  case "$1" in
    balanced) echo 25 ;;
    aggressive) echo 40 ;;
    soft) echo 10 ;;
    *) echo "" ;;
  esac
}

jitter_ms() {
  case "$1" in
    balanced) echo 50 ;;
    aggressive) echo 30 ;;
    soft) echo 60 ;;
    *) echo "" ;;
  esac
}

start_monitor_capture() {
  local run_id="$1"
  local monitor_pcap="${MONITOR_CAPTURE_DIR}/${run_id}.pcap"

  echo "[$(ts)] [*] Arrancando captura en pqc_monitor (${MONITOR_IFACE}) para ${run_id}"
  docker exec -u 0 pqc_monitor sh -lc "mkdir -p '${MONITOR_CAPTURE_DIR}' && rm -f '${monitor_pcap}'"
  docker exec -u 0 pqc_monitor sh -lc "
    dumpcap -i '${MONITOR_IFACE}' -w '${monitor_pcap}' >/tmp/${run_id}_dumpcap.log 2>&1 &
    echo \$! > /tmp/${run_id}_dumpcap.pid
  "
  sleep 1
}

stop_monitor_capture() {
  local run_id="$1"

  echo "[$(ts)] [*] Parando captura en pqc_monitor para ${run_id}"
  docker exec -u 0 pqc_monitor sh -lc "
    if [ -f /tmp/${run_id}_dumpcap.pid ]; then
      kill -INT \$(cat /tmp/${run_id}_dumpcap.pid) 2>/dev/null || true
      sleep 1
      kill -TERM \$(cat /tmp/${run_id}_dumpcap.pid) 2>/dev/null || true
      rm -f /tmp/${run_id}_dumpcap.pid
    fi
  "
}

fetch_monitor_pcap() {
  local run_id="$1"
  local src="pqc_monitor:${MONITOR_CAPTURE_DIR}/${run_id}.pcap"
  local dst="pcaps/${run_id}.pcap"

  rm -f "$dst"
  docker cp "$src" "$dst"
}

validate_pcap() {
  local run_id="$1"
  local pcap="pcaps/${run_id}.pcap"

  [[ -f "$pcap" ]] || { echo "[ERROR] No existe PCAP para ${run_id}: $pcap"; return 1; }
  capinfos "$pcap" >/dev/null 2>&1 || { echo "[ERROR] PCAP inválido para ${run_id}: $pcap"; return 1; }
}

run_one() {
  local total_conn="$1"
  local profile="$2"
  local scenario="$3"
  local idx="$4"

  local p_lc run_id
  p_lc="$(echo "$profile" | tr '[:upper:]' '[:lower:]')"
  run_id="classic_${p_lc}_${scenario}_c${total_conn}_${idx}"
  RUN_IDS+=("$run_id")

  echo "[$(ts)] === RUN START: ${run_id} ==="
  start_monitor_capture "$run_id"

  if [[ "$scenario" == "stress" ]]; then
    CLIENTS="$CLIENTS" ARRIVAL_PROFILE=stress \
      ./scripts/measure_tls_resources.sh "$run_id" "$STATS_INTERVAL" -- \
      bash -lc "./scripts/run_client_once_rafaga.sh ${run_id} ${total_conn}; sleep 3"
  else
    local pr jm
    pr="$(poisson_rate "$scenario")"
    jm="$(jitter_ms "$scenario")"

    CLIENTS="$CLIENTS" ARRIVAL_PROFILE=poisson_jitter POISSON_RATE="$pr" JITTER_MS="$jm" \
      ./scripts/measure_tls_resources.sh "$run_id" "$STATS_INTERVAL" -- \
      bash -lc "./scripts/run_client_once_rafaga.sh ${run_id} ${total_conn}; sleep 3"
  fi

  stop_monitor_capture "$run_id"
  fetch_monitor_pcap "$run_id"
  validate_pcap "$run_id"

  ./scripts/extract_metrics3.sh "$run_id"

  echo "[$(ts)] === RUN END: ${run_id} ==="
  echo
}

mkdir -p logs pcaps results

for cmd in docker bash awk sed grep capinfos; do
  command -v "$cmd" >/dev/null || { echo "[ERROR] Falta comando: $cmd"; exit 1; }
done

docker compose ps >/dev/null 2>&1 || {
  echo "[ERROR] docker compose no responde en este repositorio."
  exit 1
}

for s in \
  ./scripts/aplicar_perfil.sh \
  ./scripts/measure_tls_resources.sh \
  ./scripts/run_client_once_rafaga.sh \
  ./scripts/extract_metrics3.sh; do
  [[ -x "$s" ]] || { echo "[ERROR] Script no ejecutable o inexistente: $s"; exit 1; }
done

LOG_FILE="logs/campaign_classic_$(date +%Y%m%d_%H%M%S).log"
echo "[$(ts)] Iniciando campaña clásica. Log: ${LOG_FILE}"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(ts)] CLIENTS=${CLIENTS}"
echo "[$(ts)] RUNS_PER_SCENARIO=${RUNS_PER_SCENARIO} TOTAL_CONN_VALUES=${TOTAL_CONN_VALUES} STATS_INTERVAL=${STATS_INTERVAL}"

for total_conn in ${TOTAL_CONN_VALUES}; do
  echo "[$(ts)] ==== Iniciando bloque TOTAL_CONN=${total_conn} ===="

  for np in "${NET_PROFILES[@]}"; do
  echo "[$(ts)] ---- Aplicando perfil de red ${np} ----"
  ./scripts/aplicar_perfil.sh "$np"

    for sc in "${ARRIVAL_SCENARIOS[@]}"; do
      for n in $(seq 1 "$RUNS_PER_SCENARIO"); do
        idx="$(printf "%03d" "$n")"
        run_one "$total_conn" "$np" "$sc" "$idx"
      done
    done
  done

  echo "[$(ts)] ==== Bloque TOTAL_CONN=${total_conn} completado ===="
done

echo "[$(ts)] Campaña clásica finalizada OK."
echo "[$(ts)] RUN_IDs ejecutados:"
printf '%s\n' "${RUN_IDS[@]}"
