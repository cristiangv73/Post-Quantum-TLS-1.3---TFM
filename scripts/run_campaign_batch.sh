#!/usr/bin/env bash
set -euo pipefail

# =========================
# Configuración campaña
# =========================
CLIENTS_DEFAULT="pqc_client,pqc_client_2,pqc_client_3,pqc_client_4,pqc_client_5,pqc_client_6"
CLIENTS="${CLIENTS:-$CLIENTS_DEFAULT}"

RUNS_PER_SCENARIO="${RUNS_PER_SCENARIO:-6}"
TOTAL_CONN="${TOTAL_CONN:-1002}"
STATS_INTERVAL="${STATS_INTERVAL:-0.2}"
USE_EXTRACT3="${USE_EXTRACT3:-1}"

# Perfiles de red (README: P0..P3)
NET_PROFILES=(P0 P1 P2 P3)

# Escenarios de llegada
ARRIVAL_SCENARIOS=(balanced aggressive soft stress)

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

ts() { date +"%Y-%m-%d %H:%M:%S"; }

MONITOR_CAPTURE_DIR="${MONITOR_CAPTURE_DIR:-/tmp/captures}"
MONITOR_IFACE="${MONITOR_IFACE:-eth0}"

start_monitor_capture() {
  local run_id="$1"
  local monitor_pcap="${MONITOR_CAPTURE_DIR}/${run_id}.pcap"

  echo "[$(ts)] [*] Preparando captura en pqc_monitor (${MONITOR_IFACE}) para ${run_id}"
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

preflight_pcap() {
  local run_id="$1"
  local pcap="pcaps/${run_id}.pcap"

  if [[ ! -f "$pcap" ]]; then
    echo "[ERROR] No se generó PCAP: $pcap"
    return 1
  fi

  if ! capinfos "$pcap" >/dev/null 2>&1; then
    echo "[ERROR] PCAP inválido o corrupto: $pcap"
    return 1
  fi

  return 0
}

run_one() {
  local stack="$1"        # classic | hybrid
  local profile="$2"      # P0..P3
  local scenario="$3"     # balanced|aggressive|soft|stress
  local idx="$4"          # 001..006

  local p_lc
  p_lc="$(echo "$profile" | tr '[:upper:]' '[:lower:]')" # p0..p3
  local run_id="${stack}_${p_lc}_${scenario}_${idx}"

  local client_cmd
  if [[ "$stack" == "classic" ]]; then
    client_cmd="./scripts/run_client_once_rafaga.sh ${run_id} ${TOTAL_CONN}"
  else
    client_cmd="./scripts/run_client_once_rafaga_hibrido.sh ${run_id} ${TOTAL_CONN}"
  fi

  echo "[$(ts)] === RUN START: ${run_id} ==="

  start_monitor_capture "$run_id"

  if [[ "$scenario" == "stress" ]]; then
    CLIENTS="$CLIENTS" ARRIVAL_PROFILE=stress \
      ./scripts/measure_tls_resources.sh "$run_id" "$STATS_INTERVAL" -- \
      bash -lc "${client_cmd}; sleep 3"
  else
    local pr jm
    pr="$(poisson_rate "$scenario")"
    jm="$(jitter_ms "$scenario")"
    CLIENTS="$CLIENTS" ARRIVAL_PROFILE=poisson_jitter POISSON_RATE="$pr" JITTER_MS="$jm" \
      ./scripts/measure_tls_resources.sh "$run_id" "$STATS_INTERVAL" -- \
      bash -lc "${client_cmd}; sleep 3"
  fi

  stop_monitor_capture "$run_id"
  fetch_monitor_pcap "$run_id"

  preflight_pcap "$run_id"

  ./scripts/extract_metrics2.sh "$run_id"

  if [[ "$USE_EXTRACT3" == "1" ]]; then
    if [[ -x ./scripts/extract_metrics3.sh ]]; then
      ./scripts/extract_metrics3.sh "$run_id"
    else
      echo "[WARN] USE_EXTRACT3=1 pero scripts/extract_metrics3.sh no es ejecutable; se omite."
    fi
  fi

  echo "[$(ts)] === RUN END: ${run_id} ==="
  echo
}

mkdir -p results logs pcaps

for cmd in docker bash awk sed grep capinfos; do
  command -v "$cmd" >/dev/null || { echo "[ERROR] Falta comando: $cmd"; exit 1; }
done

docker compose ps >/dev/null 2>&1 || {
  echo "[ERROR] docker compose no responde en este repositorio."
  exit 1
}

required_scripts=(
  "./scripts/aplicar_perfil.sh"
  "./scripts/measure_tls_resources.sh"
  "./scripts/run_client_once_rafaga.sh"
  "./scripts/run_client_once_rafaga_hibrido.sh"
  "./scripts/extract_metrics2.sh"
)

for s in "${required_scripts[@]}"; do
  [[ -x "$s" ]] || { echo "[ERROR] Script no ejecutable o no existe: $s"; exit 1; }
done

LOG_FILE="logs/campaign_$(date +%Y%m%d_%H%M%S).log"
echo "[$(ts)] Iniciando campaña. Log: ${LOG_FILE}"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[$(ts)] CLIENTS=${CLIENTS}"
echo "[$(ts)] RUNS_PER_SCENARIO=${RUNS_PER_SCENARIO} TOTAL_CONN=${TOTAL_CONN} STATS_INTERVAL=${STATS_INTERVAL} USE_EXTRACT3=${USE_EXTRACT3}"

for np in "${NET_PROFILES[@]}"; do
  echo "[$(ts)] ---- Aplicando perfil de red ${np} ----"
  ./scripts/aplicar_perfil.sh "${np}"

  for stack in classic hybrid; do
    for sc in "${ARRIVAL_SCENARIOS[@]}"; do
      for n in $(seq 1 "$RUNS_PER_SCENARIO"); do
        idx="$(printf "%03d" "$n")"
        run_one "$stack" "$np" "$sc" "$idx"
      done
    done
  done
done

echo "[$(ts)] Campaña finalizada OK."
