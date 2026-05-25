#!/usr/bin/env bash
set -euo pipefail

RUN_ID="${1:?Uso: ./scripts/extract_metrics.sh classic_001}"

PCAP="pcaps/${RUN_ID}.pcap"
OUT_TXT="results/${RUN_ID}_metrics.txt"
OUT_CSV="results/${RUN_ID}_metrics.csv"
RESOURCE_SUMMARY="results/${RUN_ID}_resource_summary.txt"
RESOURCE_CSV="results/${RUN_ID}_docker_stats.csv"


require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[!] Falta dependencia requerida: $cmd" >&2
    exit 1
  fi
}

for cmd in docker tshark capinfos awk sed grep; do
  require_cmd "$cmd"
done

if ! docker info >/dev/null 2>&1; then
  echo "[!] Docker no está disponible o el daemon no responde" >&2
  exit 1
fi

mapfile -t CLIENT_CONTAINERS < <(docker ps --format '{{.Names}}' 2>/dev/null | awk '/^pqc_client(_[0-9]+)?$/ {print $0}' | sort -V)
if [ "${#CLIENT_CONTAINERS[@]}" -eq 0 ]; then
  CLIENT_CONTAINERS=(pqc_client)
fi

CLIENT_IP_FILTER=""
PRIMARY_CLIENT_IP=""
for c in "${CLIENT_CONTAINERS[@]}"; do
  ip="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c" 2>/dev/null || true)"
  [ -n "$ip" ] || continue
  if [ -z "$PRIMARY_CLIENT_IP" ]; then
    PRIMARY_CLIENT_IP="$ip"
  fi
  if [ -z "$CLIENT_IP_FILTER" ]; then
    CLIENT_IP_FILTER="ip.addr==${ip}"
  else
    CLIENT_IP_FILTER="${CLIENT_IP_FILTER} || ip.addr==${ip}"
  fi
done

if [ -z "$CLIENT_IP_FILTER" ]; then
  echo "[!] No se pudo resolver IP de clientes"
  exit 1
fi

SERVER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pqc_server)
SERVER_PORT="4433"


if [ ! -f "${PCAP}" ]; then
  echo "[!] No existe ${PCAP}"
  exit 1
fi

mkdir -p results

BASE_FILTER="(${CLIENT_IP_FILTER}) && ip.addr==${SERVER_IP} && tcp.port==${SERVER_PORT}"


count_filter() {
  local filter="$1"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && (${filter})" 2>/dev/null || true; } | wc -l | tr -d ' '
}

sum_frame_len() {
  local filter="$1"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && (${filter})" -T fields -e frame.len 2>/dev/null || true; } \
    | awk '{s+=$1} END {print s+0}'
}

sum_tcp_len() {
  local filter="$1"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && (${filter})" -T fields -e tcp.len 2>/dev/null || true; } \
    | awk '{s+=$1} END {print s+0}'
}

first_epoch() {
  local filter="$1"
  local stream_filter="${2:-}"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} ${stream_filter} && (${filter})" -T fields -e frame.time_epoch 2>/dev/null || true; } \
    | head -n 1
}

first_epoch_after() {
  local filter="$1"
  local start_epoch="$2"
  local stream_filter="${3:-}"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} ${stream_filter} && (${filter}) && frame.time_epoch>=${start_epoch}" -T fields -e frame.time_epoch 2>/dev/null || true; } \
    | head -n 1
}

last_epoch() {
  local filter="$1"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && (${filter})" -T fields -e frame.time_epoch 2>/dev/null || true; } \
    | tail -n 1
}

duration_ms() {
  local start_epoch="$1"
  local end_epoch="$2"
  if [ -n "${start_epoch}" ] && [ -n "${end_epoch}" ]; then
    awk -v s="${start_epoch}" -v e="${end_epoch}" 'BEGIN {printf "%.3f", (e-s)*1000}'
  else
    echo ""
  fi
}

max_field_value() {
  local filter="$1"
  local field="$2"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && (${filter})" -T fields -e "${field}" 2>/dev/null || true; } \
    | awk 'NF {for(i=1;i<=NF;i++) if ($i+0>m) m=$i+0} END {print m+0}'
}

avg_field_value() {
  local filter="$1"
  local field="$2"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && (${filter})" -T fields -e "${field}" 2>/dev/null || true; } \
    | awk 'NF {for(i=1;i<=NF;i++) if ($i != "") {s+=$i; n++}} END {if (n>0) printf "%.6f", s/n; else print ""}'
}

count_mtu_exceeded_packets() {
  local mtu="$1"
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && ip" -T fields -e ip.len 2>/dev/null || true; } \
    | awk -v mtu="${mtu}" '($1+0)>mtu {c++} END {print c+0}'
}

count_mss_exceeded_segments() {
  local mss="$1"
  if [ -z "${mss}" ] || [ "${mss}" = "0" ]; then
    echo "0"
    return
  fi
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tcp.len>0" -T fields -e tcp.len 2>/dev/null || true; } \
    | awk -v mss="${mss}" '($1+0)>mss {c++} END {print c+0}'
}

count_mss_exceeded_iplen_packets() {
  local mss="$1"
  if [ -z "${mss}" ] || [ "${mss}" = "0" ]; then
    echo "0"
    return
  fi
  { tshark -r "${PCAP}" -Y "${BASE_FILTER} && ip && tcp" -T fields -e ip.len 2>/dev/null || true; } \
    | awk -v mss="${mss}" '($1+0)>(mss+40) {c++} END {print c+0}'
}


get_resource_line() {
  local container="$1"
  if [ -f "${RESOURCE_SUMMARY}" ]; then
    grep "^${container} ->" "${RESOURCE_SUMMARY}" || true
  fi
}

get_resource_metric() {
  local container="$1"
  local key="$2"
  local line
  line="$(get_resource_line "$container")"

  if [ -z "$line" ]; then
    echo "NA"
    return
  fi

  case "$key" in
    cpu_avg) echo "$line" | sed -E 's/.*CPU avg=([0-9.]+)%.*/\1/' ;;
    cpu_max) echo "$line" | sed -E 's/.*CPU max=([0-9.]+)%.*/\1/' ;;
    mem_avg) echo "$line" | sed -E 's/.*MEM avg=([0-9.]+)%.*/\1/' ;;
    mem_max) echo "$line" | sed -E 's/.*MEM max=([0-9.]+)%.*/\1/' ;;
    *) echo "NA" ;;
  esac
}


get_clients_resource_metric() {
  local key="$1"
  if [ ! -f "${RESOURCE_SUMMARY}" ]; then
    echo "NA"
    return
  fi

  awk -v k="$key" '
    /^pqc_client(_[0-9]+)? ->/ {
      if (k=="cpu_avg" && match($0,/CPU avg=([0-9.]+)%/,m)) {sum+=m[1]; n++}
      else if (k=="cpu_max" && match($0,/CPU max=([0-9.]+)%/,m)) {if (m[1]>mx) mx=m[1]; n=1}
      else if (k=="mem_avg" && match($0,/MEM avg=([0-9.]+)%/,m)) {sum+=m[1]; n++}
      else if (k=="mem_max" && match($0,/MEM max=([0-9.]+)%/,m)) {if (m[1]>mx) mx=m[1]; n=1}
    }
    END {
      if (k=="cpu_avg" || k=="mem_avg") {
        if (n>0) printf "%.2f", sum/n; else printf "NA"
      } else {
        if (n>0) printf "%.2f", mx; else printf "NA"
      }
    }
  ' "${RESOURCE_SUMMARY}"
}

infer_scenario() {
  case "${RUN_ID}" in
    classic_*) echo "classic" ;;
    hybrid_*) echo "hybrid" ;;
    *) echo "unknown" ;;
  esac
}

infer_group() {
  case "${RUN_ID}" in
    classic_*) echo "X25519" ;;
    hybrid_*) echo "X25519MLKEM768" ;;
    *) echo "unknown" ;;
  esac
}

SCENARIO="$(infer_scenario)"
GROUP_NAME="$(infer_group)"

RESOURCE_SUMMARY_PRESENT="no"
RESOURCE_CSV_PRESENT="no"
if [ -f "${RESOURCE_SUMMARY}" ]; then
  RESOURCE_SUMMARY_PRESENT="yes"
fi
if [ -f "${RESOURCE_CSV}" ]; then
  RESOURCE_CSV_PRESENT="yes"
fi

PQC_CLIENT_CPU_AVG="$(get_clients_resource_metric cpu_avg)"
PQC_CLIENT_CPU_MAX="$(get_clients_resource_metric cpu_max)"
PQC_CLIENT_MEM_AVG="$(get_clients_resource_metric mem_avg)"
PQC_CLIENT_MEM_MAX="$(get_clients_resource_metric mem_max)"

PQC_SERVER_CPU_AVG="$(get_resource_metric pqc_server cpu_avg)"
PQC_SERVER_CPU_MAX="$(get_resource_metric pqc_server cpu_max)"
PQC_SERVER_MEM_AVG="$(get_resource_metric pqc_server mem_avg)"
PQC_SERVER_MEM_MAX="$(get_resource_metric pqc_server mem_max)"

PQC_MONITOR_CPU_AVG="$(get_resource_metric pqc_monitor cpu_avg)"
PQC_MONITOR_CPU_MAX="$(get_resource_metric pqc_monitor cpu_max)"
PQC_MONITOR_MEM_AVG="$(get_resource_metric pqc_monitor mem_avg)"
PQC_MONITOR_MEM_MAX="$(get_resource_metric pqc_monitor mem_max)"

PACKETS_TOTAL=$(tshark -r "${PCAP}" -Y "${BASE_FILTER}" 2>/dev/null | wc -l | tr -d ' ')
BYTES_TOTAL=$(tshark -r "${PCAP}" -Y "${BASE_FILTER}" -T fields -e frame.len 2>/dev/null \
  | awk '{s+=$1} END {print s+0}')

SYN_COUNT=$(count_filter 'tcp.flags.syn==1 && tcp.flags.ack==0')
SYNACK_COUNT=$(count_filter 'tcp.flags.syn==1 && tcp.flags.ack==1')
ACK_ONLY_COUNT=$(count_filter 'tcp.flags.ack==1 && tcp.flags.syn==0 && tcp.flags.fin==0 && tcp.flags.reset==0 && tcp.len==0')
FIN_COUNT=$(count_filter 'tcp.flags.fin==1')
RST_COUNT=$(count_filter 'tcp.flags.reset==1')

RETRANS_COUNT=$(count_filter 'tcp.analysis.retransmission')
FAST_RETRANS_COUNT=$(count_filter 'tcp.analysis.fast_retransmission')
SPURIOUS_RETRANS_COUNT=$(count_filter 'tcp.analysis.spurious_retransmission')
DUP_ACK_COUNT=$(count_filter 'tcp.analysis.duplicate_ack')
OUT_OF_ORDER_COUNT=$(count_filter 'tcp.analysis.out_of_order')
LOST_SEG_COUNT=$(count_filter 'tcp.analysis.lost_segment')

TLS_HS_TOTAL=$(count_filter 'tls.handshake')
TLS_ALERTS=$(count_filter 'tls.alert_message')

CLIENT_HELLO_COUNT=$(count_filter 'tls.handshake.type==1')
SERVER_HELLO_COUNT=$(count_filter 'tls.handshake.type==2')
ENCRYPTED_EXT_COUNT=$(count_filter 'tls.handshake.type==8')
CERTIFICATE_COUNT=$(count_filter 'tls.handshake.type==11')
CERT_VERIFY_COUNT=$(count_filter 'tls.handshake.type==15')
FINISHED_COUNT=$(count_filter 'tls.handshake.type==20')

# OJO: estos son bytes "on wire" de las tramas que contienen ese mensaje, no el tamaño interno exacto del mensaje TLS
CLIENT_HELLO_FRAME_BYTES=$(sum_frame_len 'tls.handshake.type==1')
SERVER_HELLO_FRAME_BYTES=$(sum_frame_len 'tls.handshake.type==2')

# También puede ser útil tener la carga TCP útil asociada
CLIENT_HELLO_TCP_BYTES=$(sum_tcp_len 'tls.handshake.type==1')
SERVER_HELLO_TCP_BYTES=$(sum_tcp_len 'tls.handshake.type==2')

CLIENT_HELLO_PACKETS=$(count_filter 'tls.handshake.type==1')
SERVER_HELLO_PACKETS=$(count_filter 'tls.handshake.type==2')

MAX_TCP_PAYLOAD_BYTES=$(max_field_value 'tcp.len>0' 'tcp.len')
MAX_IP_PACKET_BYTES=$(max_field_value 'ip' 'ip.len')
MAX_ETH_FRAME_BYTES=$(max_field_value 'frame' 'frame.len')
TCP_MSS_CLIENT=$(max_field_value 'tcp.flags.syn==1 && tcp.flags.ack==0 && tcp.options.mss_val' 'tcp.options.mss_val')
TCP_MSS_SERVER=$(max_field_value 'tcp.flags.syn==1 && tcp.flags.ack==1 && tcp.options.mss_val' 'tcp.options.mss_val')
TCP_MSS_NEGOTIATED=$(awk -v c="${TCP_MSS_CLIENT}" -v s="${TCP_MSS_SERVER}" 'BEGIN{print (c>0 && s>0)?(c<s?c:s):(c>0?c:s)}')
MTU_ASSUMED_BYTES=1500
MTU_EXCEEDED_IP_PACKETS=$(count_mtu_exceeded_packets "${MTU_ASSUMED_BYTES}")
MSS_EXCEEDED_SEGMENTS=$(count_mss_exceeded_segments "${TCP_MSS_NEGOTIATED}")
MSS_EXCEEDED_IP_PACKETS=$(count_mss_exceeded_iplen_packets "${TCP_MSS_NEGOTIATED}")

MTU_EXCEEDED_C2S=$(count_filter "ip.src==${PRIMARY_CLIENT_IP} && ip.len>${MTU_ASSUMED_BYTES}")
MTU_EXCEEDED_S2C=$(count_filter "ip.dst==${PRIMARY_CLIENT_IP} && ip.len>${MTU_ASSUMED_BYTES}")
if [ -n "${TCP_MSS_NEGOTIATED}" ] && [ "${TCP_MSS_NEGOTIATED}" != "0" ]; then
  MSS_EXCEEDED_C2S=$(count_filter "ip.src==${PRIMARY_CLIENT_IP} && tcp.len>${TCP_MSS_NEGOTIATED}")
  MSS_EXCEEDED_S2C=$(count_filter "ip.dst==${PRIMARY_CLIENT_IP} && tcp.len>${TCP_MSS_NEGOTIATED}")
else
  MSS_EXCEEDED_C2S=0
  MSS_EXCEEDED_S2C=0
fi

MSS_CLIENT_UNIQUE=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tcp.flags.syn==1 && tcp.flags.ack==0 && tcp.options.mss_val" -T fields -e tcp.options.mss_val 2>/dev/null || true; } | awk 'NF' | sort -u | paste -sd';' - )
MSS_SERVER_UNIQUE=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tcp.flags.syn==1 && tcp.flags.ack==1 && tcp.options.mss_val" -T fields -e tcp.options.mss_val 2>/dev/null || true; } | awk 'NF' | sort -u | paste -sd';' - )
IP_FRAGMENTED_COUNT=$(count_filter 'ip.flags.mf==1 || ip.frag_offset>0')

if [ -n "${TCP_MSS_NEGOTIATED}" ] && [ "${TCP_MSS_NEGOTIATED}" != "0" ]; then
  TCP_NEAR_MSS_LOW=$((TCP_MSS_NEGOTIATED - 60))
  TCP_NEAR_MSS_COUNT=$(count_filter "tcp.len>=${TCP_NEAR_MSS_LOW} && tcp.len<=${TCP_MSS_NEGOTIATED}")
else
  TCP_NEAR_MSS_LOW=0
  TCP_NEAR_MSS_COUNT=0
fi

CH_STREAMS=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==1" -T fields -e tcp.stream 2>/dev/null || true; } | awk 'NF' | sort -u | wc -l | tr -d ' ' )
CH_PACKETS_PER_STREAM_AVG=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==1" -T fields -e tcp.stream 2>/dev/null || true; } | awk 'NF{c[$1]++} END{for(i in c){s+=c[i];n++} if(n>0) printf "%.3f", s/n; else print ""}' )
SH_STREAMS=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==2" -T fields -e tcp.stream 2>/dev/null || true; } | awk 'NF' | sort -u | wc -l | tr -d ' ' )
SH_PACKETS_PER_STREAM_AVG=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==2" -T fields -e tcp.stream 2>/dev/null || true; } | awk 'NF{c[$1]++} END{for(i in c){s+=c[i];n++} if(n>0) printf "%.3f", s/n; else print ""}' )

TCP_ACK_RTT_AVG_S=$(avg_field_value 'tcp.analysis.ack_rtt' 'tcp.analysis.ack_rtt')
TCP_ACK_RTT_MAX_S=$(max_field_value 'tcp.analysis.ack_rtt' 'tcp.analysis.ack_rtt')
if [ -n "${TCP_ACK_RTT_AVG_S}" ]; then
  TCP_ACK_RTT_AVG_MS=$(awk -v v="${TCP_ACK_RTT_AVG_S}" 'BEGIN {printf "%.3f", v*1000}')
else
  TCP_ACK_RTT_AVG_MS=""
fi
if [ -n "${TCP_ACK_RTT_MAX_S}" ] && [ "${TCP_ACK_RTT_MAX_S}" != "0" ]; then
  TCP_ACK_RTT_MAX_MS=$(awk -v v="${TCP_ACK_RTT_MAX_S}" 'BEGIN {printf "%.3f", v*1000}')
else
  TCP_ACK_RTT_MAX_MS=""
fi

# Latencias por fase (aproximadas)
PRIMARY_TCP_STREAM=$( { tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==1" -T fields -e tcp.stream 2>/dev/null || true; } | head -n 1 )
STREAM_SCOPE=""
if [ -n "${PRIMARY_TCP_STREAM}" ]; then
  STREAM_SCOPE="&& tcp.stream==${PRIMARY_TCP_STREAM}"
fi

TCP_SYN_EPOCH=$(first_epoch 'tcp.flags.syn==1 && tcp.flags.ack==0' "${STREAM_SCOPE}")
TCP_SYNACK_EPOCH=$(first_epoch_after 'tcp.flags.syn==1 && tcp.flags.ack==1' "${TCP_SYN_EPOCH:-0}" "${STREAM_SCOPE}")
TCP_ACK_AFTER_SYNACK_EPOCH=$(first_epoch_after 'tcp.flags.ack==1 && tcp.flags.syn==0' "${TCP_SYNACK_EPOCH:-0}" "${STREAM_SCOPE}")

TLS_CLIENT_HELLO_EPOCH=$(first_epoch 'tls.handshake.type==1' "${STREAM_SCOPE}")
TLS_SERVER_HELLO_EPOCH=$(first_epoch_after 'tls.handshake.type==2' "${TLS_CLIENT_HELLO_EPOCH:-0}" "${STREAM_SCOPE}")
TLS_FIRST_FINISHED_EPOCH=$(first_epoch_after 'tls.handshake.type==20' "${TLS_SERVER_HELLO_EPOCH:-0}" "${STREAM_SCOPE}")
TLS_FIRST_APPDATA_EPOCH=$(first_epoch_after 'tls.app_data || tls.record.content_type==23' "${TLS_FIRST_FINISHED_EPOCH:-${TLS_SERVER_HELLO_EPOCH:-0}}" "${STREAM_SCOPE}")

LAT_TCP_SYN_TO_SYNACK_MS=$(duration_ms "${TCP_SYN_EPOCH}" "${TCP_SYNACK_EPOCH}")
LAT_TCP_SYNACK_TO_ACK_MS=$(duration_ms "${TCP_SYNACK_EPOCH}" "${TCP_ACK_AFTER_SYNACK_EPOCH}")
LAT_TLS_CH_TO_SH_MS=$(duration_ms "${TLS_CLIENT_HELLO_EPOCH}" "${TLS_SERVER_HELLO_EPOCH}")
LAT_TLS_SH_TO_FIN_MS=$(duration_ms "${TLS_SERVER_HELLO_EPOCH}" "${TLS_FIRST_FINISHED_EPOCH}")
LAT_TLS_FIN_TO_APPDATA_MS=$(duration_ms "${TLS_FIRST_FINISHED_EPOCH}" "${TLS_FIRST_APPDATA_EPOCH}")

# Tiempo aproximado del handshake en pcap:
# inicio = primer ClientHello
# fin = primer Finished visible después del ClientHello; si no está visible,
# se usa primer Application Data TLS como aproximación.
HS_START_EPOCH=$(first_epoch 'tls.handshake.type==1' "${STREAM_SCOPE}")
HS_END_EPOCH=""

if [ -n "${HS_START_EPOCH}" ]; then
  HS_END_EPOCH=$(first_epoch "tls.handshake.type==20 && frame.time_epoch>=${HS_START_EPOCH}" "${STREAM_SCOPE}")
fi

if [ -z "${HS_END_EPOCH}" ] && [ -n "${HS_START_EPOCH}" ]; then
  HS_END_EPOCH=$(first_epoch "tls.app_data && ip.src==${PRIMARY_CLIENT_IP} && frame.time_epoch>=${HS_START_EPOCH}" "${STREAM_SCOPE}")
fi

if [ -z "${HS_END_EPOCH}" ] && [ -n "${HS_START_EPOCH}" ]; then
  HS_END_EPOCH=$(first_epoch "tls.record.content_type==23 && ip.src==${PRIMARY_CLIENT_IP} && frame.time_epoch>=${HS_START_EPOCH}" "${STREAM_SCOPE}")
fi

if [ -n "${HS_START_EPOCH}" ] && [ -n "${HS_END_EPOCH}" ]; then
  HANDSHAKE_DURATION_MS=$(awk -v s="${HS_START_EPOCH}" -v e="${HS_END_EPOCH}" 'BEGIN {printf "%.3f", (e-s)*1000}')
else
  HANDSHAKE_DURATION_MS=""
fi

{
  echo "=== INFO GENERAL ==="
  echo "RUN_ID: ${RUN_ID}"
  echo "Scenario: ${SCENARIO}"
  echo "Group: ${GROUP_NAME}"
  echo "PCAP: ${PCAP}"
  echo "Clients detected: ${CLIENT_CONTAINERS[*]}"
  echo "Base filter: ${BASE_FILTER}"
  echo "Primary tcp.stream for latency metrics: ${PRIMARY_TCP_STREAM}"

  echo
  echo "=== CAPINFOS ==="
  capinfos "${PCAP}"

  echo
  echo "=== TLS HANDSHAKES ==="
  tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake" || true

  echo
  echo "=== CLIENT HELLO ==="
  tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==1" || true

  echo
  echo "=== SERVER HELLO ==="
  tshark -r "${PCAP}" -Y "${BASE_FILTER} && tls.handshake.type==2" || true

  echo
  echo "=== TCP CONTROL ==="
  echo "SYN: ${SYN_COUNT}"
  echo "SYN-ACK: ${SYNACK_COUNT}"
  echo "ACK-only: ${ACK_ONLY_COUNT}"
  echo "FIN: ${FIN_COUNT}"
  echo "RST: ${RST_COUNT}"

  echo
  echo "=== TCP ANOMALIAS ==="
  echo "Retransmissions: ${RETRANS_COUNT}"
  echo "Fast Retransmissions: ${FAST_RETRANS_COUNT}"
  echo "Spurious Retransmissions: ${SPURIOUS_RETRANS_COUNT}"
  echo "Duplicate ACK: ${DUP_ACK_COUNT}"
  echo "Out of order: ${OUT_OF_ORDER_COUNT}"
  echo "Lost segments: ${LOST_SEG_COUNT}"

  echo
  echo "=== TLS METRICAS ==="
  echo "TLS handshake messages total: ${TLS_HS_TOTAL}"
  echo "TLS alerts: ${TLS_ALERTS}"
  echo "ClientHello count: ${CLIENT_HELLO_COUNT}"
  echo "ServerHello count: ${SERVER_HELLO_COUNT}"
  echo "EncryptedExtensions count: ${ENCRYPTED_EXT_COUNT}"
  echo "Certificate count: ${CERTIFICATE_COUNT}"
  echo "CertificateVerify count: ${CERT_VERIFY_COUNT}"
  echo "Finished count: ${FINISHED_COUNT}"

  echo
  echo "=== VOLUMEN / SEGMENTACION ==="
  echo "Packets total: ${PACKETS_TOTAL}"
  echo "Bytes total: ${BYTES_TOTAL}"
  echo "ClientHello packets: ${CLIENT_HELLO_PACKETS}"
  echo "ServerHello packets: ${SERVER_HELLO_PACKETS}"
  echo "ClientHello frame bytes: ${CLIENT_HELLO_FRAME_BYTES}"
  echo "ServerHello frame bytes: ${SERVER_HELLO_FRAME_BYTES}"
  echo "ClientHello tcp payload bytes: ${CLIENT_HELLO_TCP_BYTES}"
  echo "ServerHello tcp payload bytes: ${SERVER_HELLO_TCP_BYTES}"
  echo "Max TCP payload bytes: ${MAX_TCP_PAYLOAD_BYTES}"
  echo "Max IP packet bytes (ip.len): ${MAX_IP_PACKET_BYTES}"
  echo "Max Ethernet frame bytes (frame.len): ${MAX_ETH_FRAME_BYTES}"
  echo "TCP MSS client advertised: ${TCP_MSS_CLIENT}"
  echo "TCP MSS server advertised: ${TCP_MSS_SERVER}"
  echo "TCP MSS negotiated (approx): ${TCP_MSS_NEGOTIATED}"
  echo "MTU assumed bytes (L3): ${MTU_ASSUMED_BYTES}"
  echo "Packets exceeding MTU assumed (ip.len > ${MTU_ASSUMED_BYTES}): ${MTU_EXCEEDED_IP_PACKETS}"
  echo "Packets exceeding MTU client->server (ip.len > ${MTU_ASSUMED_BYTES}): ${MTU_EXCEEDED_C2S}"
  echo "Packets exceeding MTU server->client (ip.len > ${MTU_ASSUMED_BYTES}): ${MTU_EXCEEDED_S2C}"
  echo "TCP segments exceeding negotiated MSS (tcp.len > MSS): ${MSS_EXCEEDED_SEGMENTS}"
  echo "IP packets exceeding negotiated MSS estimate (ip.len > MSS+40): ${MSS_EXCEEDED_IP_PACKETS}"
  echo "TCP segments > MSS client->server: ${MSS_EXCEEDED_C2S}"
  echo "TCP segments > MSS server->client: ${MSS_EXCEEDED_S2C}"
  echo "MSS unique values in SYN (client): ${MSS_CLIENT_UNIQUE}"
  echo "MSS unique values in SYN-ACK (server): ${MSS_SERVER_UNIQUE}"
  echo "IP fragmented packets count: ${IP_FRAGMENTED_COUNT}"
  echo "TCP near-MSS window [${TCP_NEAR_MSS_LOW},${TCP_MSS_NEGOTIATED}] count: ${TCP_NEAR_MSS_COUNT}"
  echo "ClientHello streams: ${CH_STREAMS}"
  echo "ClientHello packets per stream avg: ${CH_PACKETS_PER_STREAM_AVG}"
  echo "ServerHello streams: ${SH_STREAMS}"
  echo "ServerHello packets per stream avg: ${SH_PACKETS_PER_STREAM_AVG}"
  echo "TCP ACK RTT avg (ms, tshark tcp.analysis.ack_rtt): ${TCP_ACK_RTT_AVG_MS}"
  echo "TCP ACK RTT max (ms, tshark tcp.analysis.ack_rtt): ${TCP_ACK_RTT_MAX_MS}"
  echo "Lat TCP SYN -> SYN-ACK (ms): ${LAT_TCP_SYN_TO_SYNACK_MS}"
  echo "Lat TCP SYN-ACK -> ACK (ms): ${LAT_TCP_SYNACK_TO_ACK_MS}"
  echo "Lat TLS ClientHello -> ServerHello (ms): ${LAT_TLS_CH_TO_SH_MS}"
  echo "Lat TLS ServerHello -> Finished (ms): ${LAT_TLS_SH_TO_FIN_MS}"
  echo "Lat TLS Finished -> AppData (ms): ${LAT_TLS_FIN_TO_APPDATA_MS}"

  echo
  echo "=== TIEMPO APROX HANDSHAKE DESDE PCAP ==="
  echo "Handshake start epoch: ${HS_START_EPOCH}"
  echo "Handshake end epoch: ${HS_END_EPOCH}"
  echo "Handshake duration ms (approx): ${HANDSHAKE_DURATION_MS}"

  echo
  echo "=== RECURSOS CPU/MEM (docker stats) ==="
  echo "Resource summary file: ${RESOURCE_SUMMARY} (present: ${RESOURCE_SUMMARY_PRESENT})"
  echo "Resource raw csv file: ${RESOURCE_CSV} (present: ${RESOURCE_CSV_PRESENT})"
  echo "pqc_clients CPU avg (%): ${PQC_CLIENT_CPU_AVG}"
  echo "pqc_clients CPU max (%): ${PQC_CLIENT_CPU_MAX}"
  echo "pqc_clients MEM avg (%): ${PQC_CLIENT_MEM_AVG}"
  echo "pqc_clients MEM max (%): ${PQC_CLIENT_MEM_MAX}"
  echo "pqc_server CPU avg (%): ${PQC_SERVER_CPU_AVG}"
  echo "pqc_server CPU max (%): ${PQC_SERVER_CPU_MAX}"
  echo "pqc_server MEM avg (%): ${PQC_SERVER_MEM_AVG}"
  echo "pqc_server MEM max (%): ${PQC_SERVER_MEM_MAX}"
  echo "pqc_monitor CPU avg (%): ${PQC_MONITOR_CPU_AVG}"
  echo "pqc_monitor CPU max (%): ${PQC_MONITOR_CPU_MAX}"
  echo "pqc_monitor MEM avg (%): ${PQC_MONITOR_MEM_AVG}"
  echo "pqc_monitor MEM max (%): ${PQC_MONITOR_MEM_MAX}"

  if [ -f "${RESOURCE_SUMMARY}" ]; then
    echo
    echo "--- raw resource summary ---"
    cat "${RESOURCE_SUMMARY}"
  fi

  echo
  echo "=== IO STAT ==="
  tshark -r "${PCAP}" -Y "${BASE_FILTER}" -q -z io,stat,0 || true
} > "${OUT_TXT}"

{
  echo "run_id,scenario,group_name,packets_total,bytes_total,syn_count,synack_count,ack_only_count,fin_count,rst_count,retransmissions,fast_retransmissions,spurious_retransmissions,duplicate_ack,out_of_order,lost_segments,tls_handshake_total,tls_alerts,clienthello_count,serverhello_count,encryptedextensions_count,certificate_count,certificateverify_count,finished_count,clienthello_packets,serverhello_packets,clienthello_frame_bytes,serverhello_frame_bytes,clienthello_tcp_bytes,serverhello_tcp_bytes,max_tcp_payload_bytes,max_ip_packet_bytes,max_eth_frame_bytes,tcp_mss_client,tcp_mss_server,tcp_mss_negotiated,mtu_assumed_bytes,mtu_exceeded_ip_packets,mtu_exceeded_c2s,mtu_exceeded_s2c,mss_exceeded_segments,mss_exceeded_ip_packets,mss_exceeded_c2s,mss_exceeded_s2c,mss_client_unique,mss_server_unique,ip_fragmented_count,tcp_near_mss_low,tcp_near_mss_count,ch_streams,ch_packets_per_stream_avg,sh_streams,sh_packets_per_stream_avg,tcp_ack_rtt_avg_ms,tcp_ack_rtt_max_ms,lat_tcp_syn_to_synack_ms,lat_tcp_synack_to_ack_ms,lat_tls_ch_to_sh_ms,lat_tls_sh_to_fin_ms,lat_tls_fin_to_appdata_ms,handshake_duration_ms_pcap,resource_summary_present,resource_csv_present,pqc_client_cpu_avg,pqc_client_cpu_max,pqc_client_mem_avg,pqc_client_mem_max,pqc_server_cpu_avg,pqc_server_cpu_max,pqc_server_mem_avg,pqc_server_mem_max,pqc_monitor_cpu_avg,pqc_monitor_cpu_max,pqc_monitor_mem_avg,pqc_monitor_mem_max"
  echo "${RUN_ID},${SCENARIO},${GROUP_NAME},${PACKETS_TOTAL},${BYTES_TOTAL},${SYN_COUNT},${SYNACK_COUNT},${ACK_ONLY_COUNT},${FIN_COUNT},${RST_COUNT},${RETRANS_COUNT},${FAST_RETRANS_COUNT},${SPURIOUS_RETRANS_COUNT},${DUP_ACK_COUNT},${OUT_OF_ORDER_COUNT},${LOST_SEG_COUNT},${TLS_HS_TOTAL},${TLS_ALERTS},${CLIENT_HELLO_COUNT},${SERVER_HELLO_COUNT},${ENCRYPTED_EXT_COUNT},${CERTIFICATE_COUNT},${CERT_VERIFY_COUNT},${FINISHED_COUNT},${CLIENT_HELLO_PACKETS},${SERVER_HELLO_PACKETS},${CLIENT_HELLO_FRAME_BYTES},${SERVER_HELLO_FRAME_BYTES},${CLIENT_HELLO_TCP_BYTES},${SERVER_HELLO_TCP_BYTES},${MAX_TCP_PAYLOAD_BYTES},${MAX_IP_PACKET_BYTES},${MAX_ETH_FRAME_BYTES},${TCP_MSS_CLIENT},${TCP_MSS_SERVER},${TCP_MSS_NEGOTIATED},${MTU_ASSUMED_BYTES},${MTU_EXCEEDED_IP_PACKETS},${MTU_EXCEEDED_C2S},${MTU_EXCEEDED_S2C},${MSS_EXCEEDED_SEGMENTS},${MSS_EXCEEDED_IP_PACKETS},${MSS_EXCEEDED_C2S},${MSS_EXCEEDED_S2C},${MSS_CLIENT_UNIQUE},${MSS_SERVER_UNIQUE},${IP_FRAGMENTED_COUNT},${TCP_NEAR_MSS_LOW},${TCP_NEAR_MSS_COUNT},${CH_STREAMS},${CH_PACKETS_PER_STREAM_AVG},${SH_STREAMS},${SH_PACKETS_PER_STREAM_AVG},${TCP_ACK_RTT_AVG_MS},${TCP_ACK_RTT_MAX_MS},${LAT_TCP_SYN_TO_SYNACK_MS},${LAT_TCP_SYNACK_TO_ACK_MS},${LAT_TLS_CH_TO_SH_MS},${LAT_TLS_SH_TO_FIN_MS},${LAT_TLS_FIN_TO_APPDATA_MS},${HANDSHAKE_DURATION_MS},${RESOURCE_SUMMARY_PRESENT},${RESOURCE_CSV_PRESENT},${PQC_CLIENT_CPU_AVG},${PQC_CLIENT_CPU_MAX},${PQC_CLIENT_MEM_AVG},${PQC_CLIENT_MEM_MAX},${PQC_SERVER_CPU_AVG},${PQC_SERVER_CPU_MAX},${PQC_SERVER_MEM_AVG},${PQC_SERVER_MEM_MAX},${PQC_MONITOR_CPU_AVG},${PQC_MONITOR_CPU_MAX},${PQC_MONITOR_MEM_AVG},${PQC_MONITOR_MEM_MAX}"
} > "${OUT_CSV}"

echo "[*] Métricas TXT guardadas en ${OUT_TXT}"
echo "[*] Métricas CSV guardadas en ${OUT_CSV}"
