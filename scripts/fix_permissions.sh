#!/usr/bin/env bash

echo "[*] Corrigiendo propietarios..."
sudo chown -R cristian:cristian pcaps results scripts

echo "[*] Corrigiendo permisos..."
chmod -R 755 scripts
chmod -R 755 pcaps results
chmod 644 results/*.txt 2>/dev/null
chmod 644 pcaps/*.pcap 2>/dev/null

echo "[*] Permisos OK"
