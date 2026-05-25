#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:?Uso: ./scripts/fix_pcap_permissions.sh classic_001}"
FILE="pcaps/${RUN_ID}.pcap"

sudo chown "$USER:$USER" "$FILE"
chmod 644 "$FILE"

ls -l "$FILE"
