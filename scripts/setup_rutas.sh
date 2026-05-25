#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/client_utils.sh
source "${SCRIPT_DIR}/client_utils.sh"

while IFS= read -r client; do
  [ -n "$client" ] || continue
  docker exec "$client" ip route replace 192.168.0.0/24 via 172.20.0.2
  echo "[*] Ruta aplicada en ${client}"
done < <(resolve_clients)

docker exec pqc_server ip route replace 172.20.0.0/24 via 192.168.0.2
echo "[*] Ruta aplicada en pqc_server"
