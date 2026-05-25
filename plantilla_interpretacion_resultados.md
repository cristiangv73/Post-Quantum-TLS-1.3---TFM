# Plantilla de interpretación estándar (por ejecución)

## 1) Resumen ejecutivo (3 líneas)
- **Carga observada:** `<ClientHello count>` intentos TLS, `<Packets total>` paquetes, `<Bytes total>` bytes en `<Duration>` s.
- **Latencia de establecimiento (KPI):** `CH->SH p50/p95/p99 = <...>/<...>/<...> ms` (N=`<lat_tls_ch_to_sh_n>`).
- **Capacidad/éxito:** throughput global `<handshake_throughput_global_hsps>` hs/s, éxito `<handshake_success_rate_pct>%` (completados `<handshake_streams_complete>/<handshake_streams_ch_total>`).

---

## 2) Calidad de datos y validez
- **Handshake heurístico:** `handshake_duration_quality = <ok|insufficient_samples|no_samples>`, `N=<handshake_duration_n_pcap>`, umbral fallback=`<HS_APPDATA_FALLBACK_MAX_MS>` ms.
- **Visibilidad TLS estricta:** `Finished count = <finished_count>` (si es 0, interpretar `handshake_duration_*` como aproximación por fallback).
- **Control de red base:** `TCP ACK RTT p95 = <tcp_ack_rtt_p95_ms> ms` y retransmisiones `<retransmissions>`.

---

## 3) Diagnóstico técnico breve
- **Si RTT bajo + CH->SH alto:** probable cuello de **cómputo/cola** (no red).
- **Si retransmisiones/dupACK altos:** posible impacto de **transporte/red**.
- **Si success rate bajo con Finished=0:** posible limitación de visibilidad + fallback estricto (no asumir fallo criptográfico directo sin más evidencia).

---

## 4) Comparativa Clásico vs Híbrido (bloque fijo)
- **Latencia:** comparar `CH->SH p95/p99` (principal).
- **Capacidad:** comparar `handshake_throughput_global_hsps` y `p95_hsps`.
- **Robustez:** comparar `handshake_success_rate_pct`.
- **Overhead:** comparar `hello_payload_expansion_ratio` y `tls_hs_bytes_per_connection` (+ p50 si disponible).
- **Cómputo:** comparar `pqc_server_cpu_avg/max` y `pqc_clients_cpu_avg/max`.

---

## 5) Semáforo rápido (rellenable)

- **Latencia CH->SH (p95):** 🟢/🟡/🔴 = `<valor>` ms
- **Throughput global:** 🟢/🟡/🔴 = `<valor>` hs/s
- **Success rate:** 🟢/🟡/🔴 = `<valor>` %
- **Calidad handshake_duration:** 🟢/🟡/🔴 = `<quality>` (`N=<n>`)

> Define tus umbrales de color una vez por campaña y no los cambies a mitad.

---

## Mini versión ultra-corta (para tabla resumen)

**Run `<RUN_ID>`** — CH->SH p95=`<...>` ms (N=`<...>`), throughput=`<...>` hs/s, success=`<...>%`, server CPU avg=`<...>%`, quality=`<...>`.
