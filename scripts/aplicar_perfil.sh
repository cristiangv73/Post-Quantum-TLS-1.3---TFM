#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-P0}"
MONITOR_CONTAINER="pqc_monitor"

echo "[*] Aplicando perfil ${PROFILE}"

# Limpiar qdisc
docker exec ${MONITOR_CONTAINER} tc qdisc del dev eth0 root 2>/dev/null || true
docker exec ${MONITOR_CONTAINER} tc qdisc del dev eth1 root 2>/dev/null || true

case "$PROFILE" in
  P0)
    echo "[*] Perfil P0 (sin degradación)"
    ;;

  P1)
    docker exec ${MONITOR_CONTAINER} tc qdisc add dev eth0 root netem delay 15ms
    docker exec ${MONITOR_CONTAINER} tc qdisc add dev eth1 root netem delay 15ms
    ;;

  P2)
    docker exec ${MONITOR_CONTAINER} tc qdisc add dev eth0 root netem delay 25ms loss 0.1%
    docker exec ${MONITOR_CONTAINER} tc qdisc add dev eth1 root netem delay 25ms loss 0.1%
    ;;

  P3)
    docker exec ${MONITOR_CONTAINER} tc qdisc add dev eth0 root netem delay 50ms loss 1%
    docker exec ${MONITOR_CONTAINER} tc qdisc add dev eth1 root netem delay 50ms loss 1%
    ;;

  *)
    echo "[!] Perfil no válido"
    exit 1
    ;;
esac

echo
echo "[*] Estado qdisc en monitor:"
docker exec ${MONITOR_CONTAINER} tc qdisc show dev eth0
docker exec ${MONITOR_CONTAINER} tc qdisc show dev eth1
