#!/bin/sh
set -e

ip route replace 192.168.0.0/24 via 172.20.0.2

echo "[client] routing table:"
ip route

exec tail -f /dev/null
