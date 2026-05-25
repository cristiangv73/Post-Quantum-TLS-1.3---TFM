#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Uso:
  ./scripts/measure_tls_resources.sh RUN_ID [INTERVAL_S] [DURATION_S]
  ./scripts/measure_tls_resources.sh RUN_ID [INTERVAL_S] -- <comando TLS>

Ejemplos:
  ./scripts/measure_tls_resources.sh classic_cpu 1 -- ./scripts/run_client_once.sh classic_cpu
  ./scripts/measure_tls_resources.sh rafaga_cpu 1 -- ./scripts/run_client_once_rafaga.sh rafaga_cpu
  ./scripts/measure_tls_resources.sh baseline_idle 1 30
USAGE
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

RUN_ID="$1"
shift

INTERVAL_S="${1:-1}"
if [ "$#" -gt 0 ]; then
  shift || true
fi

DURATION_S=""
CMD=()

if [ "${1:-}" = "--" ]; then
  shift
  CMD=("$@")
elif [ "$#" -gt 0 ]; then
  DURATION_S="$1"
  shift || true
  if [ "${1:-}" = "--" ]; then
    shift
    CMD=("$@")
  fi
fi

if [ -z "$DURATION_S" ] && [ "${#CMD[@]}" -eq 0 ]; then
  DURATION_S=30
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[!] docker no está disponible en PATH"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "[!] docker está instalado pero el daemon no responde"
  exit 1
fi

mapfile -t CLIENT_CONTAINERS < <(docker ps --format "{{.Names}}" | awk '/^pqc_client(_[0-9]+)?$/ {print $0}' | sort -V)
if [ "${#CLIENT_CONTAINERS[@]}" -eq 0 ]; then
  CLIENT_CONTAINERS=(pqc_client)
fi
CONTAINERS=("${CLIENT_CONTAINERS[@]}" pqc_server pqc_monitor)
mkdir -p results

CSV="results/${RUN_ID}_docker_stats.csv"
SUMMARY="results/${RUN_ID}_resource_summary.txt"

{
  echo "timestamp;container;cpu_perc;mem_usage;mem_perc;net_io;block_io;pids"
} > "$CSV"

sample_once() {
  local ts c line stats
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

  declare -A stats_by_container=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    c="${line%%;*}"
    stats="${line#*;}"
    stats_by_container["$c"]="$stats"
  done < <(docker stats --no-stream     --format '{{.Name}};{{.CPUPerc}};{{.MemUsage}};{{.MemPerc}};{{.NetIO}};{{.BlockIO}};{{.PIDs}}'     "${CONTAINERS[@]}" 2>/dev/null || true)

  for c in "${CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -Fxq "$c"; then
      if [ -n "${stats_by_container[$c]:-}" ]; then
        echo "${ts};${c};${stats_by_container[$c]}" >> "$CSV"
      else
        echo "${ts};${c};N/A;N/A;N/A;N/A;N/A;N/A" >> "$CSV"
      fi
    else
      echo "${ts};${c};DOWN;DOWN;DOWN;DOWN;DOWN;DOWN" >> "$CSV"
    fi
  done
}

monitor_for_duration() {
  local elapsed=0
  while awk -v e="$elapsed" -v d="$DURATION_S" 'BEGIN {exit !(e < d)}'; do
    sample_once
    sleep "$INTERVAL_S"
    elapsed="$(awk -v e="$elapsed" -v i="$INTERVAL_S" 'BEGIN {printf "%.6f", e+i}')"
  done
}

monitor_while_pid_alive() {
  local pid="$1"
  while kill -0 "$pid" >/dev/null 2>&1; do
    sample_once
    sleep "$INTERVAL_S"
  done
  sample_once
}

echo "[*] Guardando muestras en: $CSV"

if [ "${#CMD[@]}" -gt 0 ]; then
  echo "[*] Ejecutando comando medido: ${CMD[*]}"
  "${CMD[@]}" &
  CMD_PID=$!
  monitor_while_pid_alive "$CMD_PID"
  wait "$CMD_PID" || true
else
  echo "[*] Modo duración fija: ${DURATION_S}s (intervalo ${INTERVAL_S}s)"
  monitor_for_duration
fi

{
  echo "RUN_ID: ${RUN_ID}"
  echo "CSV: ${CSV}"
  echo
  echo "=== Resumen CPU% y MEM% (avg / max) por contenedor ==="
  awk -F';' '
    NR==1 {next}
    $3 ~ /DOWN|N\/A/ {next}
    {
      c=$2
      cpu=$3; gsub(/%/, "", cpu); gsub(/,/, ".", cpu); cpu+=0
      memp=$5; gsub(/%/, "", memp); gsub(/,/, ".", memp); memp+=0
      cpu_sum[c]+=cpu; cpu_n[c]++; if(!(c in cpu_max) || cpu>cpu_max[c]) cpu_max[c]=cpu
      mem_sum[c]+=memp; mem_n[c]++; if(!(c in mem_max) || memp>mem_max[c]) mem_max[c]=memp
    }
    END {
      for (c in cpu_sum) {
        cpu_avg = (cpu_n[c] ? cpu_sum[c]/cpu_n[c] : 0)
        mem_avg = (mem_n[c] ? mem_sum[c]/mem_n[c] : 0)
        printf "%s -> CPU avg=%.2f%%, CPU max=%.2f%%, MEM avg=%.2f%%, MEM max=%.2f%%\n", c, cpu_avg, cpu_max[c], mem_avg, mem_max[c]
      }
    }
  ' "$CSV"
} > "$SUMMARY"

echo "[*] Resumen guardado en: $SUMMARY"
cat "$SUMMARY"
