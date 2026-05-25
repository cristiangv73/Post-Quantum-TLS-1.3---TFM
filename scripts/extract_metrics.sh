#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:?Uso: ./scripts/extract_metrics.sh classic_001}"
PCAP="pcaps/${RUN_ID}.pcap"
OUT="results/${RUN_ID}_metrics.txt"

if [ ! -f "${PCAP}" ]; then
  echo "[!] No existe ${PCAP}"
  exit 1
fi

count_filter() {
  local filter="$1"
  tshark -r "${PCAP}" -Y "${filter}" 2>/dev/null | wc -l
}

sum_frame_len() {
  local filter="$1"
  tshark -r "${PCAP}" -Y "${filter}" -T fields -e frame.len 2>/dev/null \
    | awk '{s+=$1} END {print s+0}'
}

{
  echo "=== CAPINFOS ==="
  capinfos "${PCAP}"

  echo
  echo "=== TLS HANDSHAKES ==="
  tshark -r "${PCAP}" -Y "tls.handshake" || true

  echo
  echo "=== CLIENT HELLO ==="
  tshark -r "${PCAP}" -Y "tls.handshake.type==1" || true

  echo
  echo "=== SERVER HELLO ==="
  tshark -r "${PCAP}" -Y "tls.handshake.type==2" || true

  echo
  echo "=== TCP CONTROL ==="
  echo "SYN: $(count_filter 'tcp.flags.syn==1 && tcp.flags.ack==0')"
  echo "SYN-ACK: $(count_filter 'tcp.flags.syn==1 && tcp.flags.ack==1')"
  echo "ACK-only: $(count_filter 'tcp.flags.ack==1 && tcp.flags.syn==0 && tcp.flags.fin==0 && tcp.flags.reset==0 && tcp.len==0')"
  echo "FIN: $(count_filter 'tcp.flags.fin==1')"
  echo "RST: $(count_filter 'tcp.flags.reset==1')"

  echo
  echo "=== TCP ANOMALIAS ==="
  echo "Retransmissions: $(count_filter 'tcp.analysis.retransmission')"
  echo "Fast Retransmissions: $(count_filter 'tcp.analysis.fast_retransmission')"
  echo "Spurious Retransmissions: $(count_filter 'tcp.analysis.spurious_retransmission')"
  echo "Duplicate ACK: $(count_filter 'tcp.analysis.duplicate_ack')"
  echo "Out of order: $(count_filter 'tcp.analysis.out_of_order')"
  echo "Lost segments: $(count_filter 'tcp.analysis.lost_segment')"

  echo
  echo "=== TLS METRICAS ==="
  echo "TLS handshake messages total: $(count_filter 'tls.handshake')"
  echo "TLS alerts: $(count_filter 'tls.alert_message')"
  echo "ClientHello count: $(count_filter 'tls.handshake.type==1')"
  echo "ServerHello count: $(count_filter 'tls.handshake.type==2')"
  echo "EncryptedExtensions count: $(count_filter 'tls.handshake.type==8')"
  echo "Certificate count: $(count_filter 'tls.handshake.type==11')"
  echo "CertificateVerify count: $(count_filter 'tls.handshake.type==15')"
  echo "Finished count: $(count_filter 'tls.handshake.type==20')"

  echo
  echo "=== VOLUMEN / SEGMENTACION ==="
  echo "Packets total: $(tshark -r "${PCAP}" 2>/dev/null | wc -l)"
  echo "Bytes total: $(tshark -r "${PCAP}" -T fields -e frame.len 2>/dev/null | awk '{s+=$1} END {print s+0}')"
  echo "ClientHello bytes: $(sum_frame_len 'tls.handshake.type==1')"
  echo "ServerHello bytes: $(sum_frame_len 'tls.handshake.type==2')"

  echo
  echo "=== IO STAT ==="
  tshark -r "${PCAP}" -q -z io,stat,0 || true

} > "${OUT}"

echo "[*] Métricas guardadas en ${OUT}"
