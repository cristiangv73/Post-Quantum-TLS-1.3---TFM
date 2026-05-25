#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/client_utils.sh
source "${SCRIPT_DIR}/client_utils.sh"

RUN_ID="${1:-hybrid_rafaga_001}"
TOTAL_CONN="${2:-200}"
SERVER_IP="${3:-192.168.0.10}"
SERVER_PORT="${4:-4433}"
ARRIVAL_PROFILE="${ARRIVAL_PROFILE:-poisson_jitter}"
POISSON_RATE="${POISSON_RATE:-20}"
JITTER_MS="${JITTER_MS:-35}"

if ! awk -v r="$POISSON_RATE" 'BEGIN{exit !(r+0>0)}'; then
  echo "[!] POISSON_RATE debe ser > 0 (valor actual: ${POISSON_RATE})"
  exit 1
fi

mapfile -t CLIENTS_ARR < <(resolve_clients)
if [ "${#CLIENTS_ARR[@]}" -eq 0 ]; then
  echo "[!] No se encontraron clientes para ejecutar la ráfaga"
  exit 1
fi

mkdir -p results
rm -f "results/${RUN_ID}_client.txt" "results/${RUN_ID}_client_err.txt"
: > "results/${RUN_ID}_client.txt"
: > "results/${RUN_ID}_client_err.txt"

clients_count="${#CLIENTS_ARR[@]}"
declare -A IDS_BY_CLIENT

for ((i=1; i<=TOTAL_CONN; i++)); do
  idx=$(((i - 1) % clients_count))
  c="${CLIENTS_ARR[$idx]}"
  IDS_BY_CLIENT["$c"]+=" $i"
done

if [ "$ARRIVAL_PROFILE" = "stress" ]; then
  echo "[*] Perfil stress: conexiones totalmente paralelas por cliente" >> "results/${RUN_ID}_client.txt"
else
  echo "[*] Perfil ${ARRIVAL_PROFILE}: llegadas no sincronizadas con Poisson+jitter" >> "results/${RUN_ID}_client.txt"
fi

declare -A START_DELAYS
for ((i=1; i<=TOTAL_CONN; i++)); do
  if [ "$ARRIVAL_PROFILE" = "stress" ]; then
    START_DELAYS[$i]="0"
  else
    delay="$(awk -v r="$POISSON_RATE" -v j="$JITTER_MS" 'BEGIN{srand();u=rand();if (u<1e-12) u=1e-12;ia=-log(1-u)/r;jitter=((rand()*2-1)*j)/1000;d=ia+jitter;if(d<0)d=0;printf "%.6f", d}')"
    START_DELAYS[$i]="$delay"
  fi
done

pids=()
for client in "${CLIENTS_ARR[@]}"; do
  ids="${IDS_BY_CLIENT[$client]:-}"
  ids="$(echo "$ids" | xargs)"
  [ -n "$ids" ] || continue

  launch_plan=""
  for i in $ids; do
    launch_plan+="${i}:${START_DELAYS[$i]} "
  done
  launch_plan="$(echo "$launch_plan" | xargs)"

  echo "[*] ${client} <= plan: ${launch_plan}" >> "results/${RUN_ID}_client.txt"

  docker exec "$client" sh -lc '
ok=0
err=0
PIDS=""
rm -f /tmp/'"${RUN_ID}"'_out_*.txt /tmp/'"${RUN_ID}"'_err_*.txt
for pair in '"${launch_plan}"'; do
  i="${pair%%:*}"
  delay="${pair##*:}"
  (
    sleep "$delay"
    openssl s_client \
      -connect '"${SERVER_IP}:${SERVER_PORT}"' \
      -CAfile /certs/ca/ca.crt \
      -tls1_3 \
      -groups X25519MLKEM768 \
      -provider default \
      -provider oqsprovider \
      < /dev/null > /tmp/'"${RUN_ID}"'_out_${i}.txt 2> /tmp/'"${RUN_ID}"'_err_${i}.txt
  ) &
  PIDS="${PIDS} $!"
done

for pid in ${PIDS}; do
  if wait "$pid"; then
    ok=$((ok+1))
  else
    err=$((err+1))
  fi
done

cat /tmp/'"${RUN_ID}"'_out_*.txt 2>/dev/null > /results/'"${RUN_ID}"'_'"${client}"'_client.txt || true
cat /tmp/'"${RUN_ID}"'_err_*.txt 2>/dev/null > /results/'"${RUN_ID}"'_'"${client}"'_client_err.txt || true
echo "client='"${client}"' total='"$(wc -w <<< "$ids")"' ok=${ok} err=${err}" > /results/'"${RUN_ID}"'_'"${client}"'_summary.txt
' &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "$pid" || true
done

for client in "${CLIENTS_ARR[@]}"; do
  cat "results/${RUN_ID}_${client}_summary.txt" >> "results/${RUN_ID}_client.txt" 2>/dev/null || true
  cat "results/${RUN_ID}_${client}_client_err.txt" >> "results/${RUN_ID}_client_err.txt" 2>/dev/null || true
done

echo "[*] Ráfaga híbrida completada: ${TOTAL_CONN} conexiones en ${clients_count} clientes (${ARRIVAL_PROFILE})"
echo "=== host results ==="
ls -l results | grep "${RUN_ID}" || true
echo "=== resumen por cliente ==="
sed -n "1,160p" "results/${RUN_ID}_client.txt" || true
