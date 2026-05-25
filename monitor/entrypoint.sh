#!/bin/sh
set -e

# Habilitar reenvío IP
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[monitor] ip_forward:"
cat /proc/sys/net/ipv4/ip_forward

echo "[monitor] interfaces:"
ip addr

echo "[monitor] routing table:"
ip route

exec tail -f /dev/null
