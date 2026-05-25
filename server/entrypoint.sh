#!/bin/sh
set -e

ip route replace 172.20.0.0/24 via 192.168.0.2

echo "[server] routing table:"
ip route

exec tail -f /dev/null
