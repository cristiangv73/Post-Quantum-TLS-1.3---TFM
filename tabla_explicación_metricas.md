# Guía de métricas de `scripts/extract_metrics3.sh`

## Tabla por secciones (orden de salida TXT)

### 1) TCP CONTROL

| Métrica | Qué significa | Para qué sirve | Campo/filtro tshark base |
|---|---|---|---|
| SYN | Número de inicios TCP (cliente abre conexión). | Estima cuántas conexiones se intentan abrir; base para comparar con `SYN-ACK` y detectar rechazos. | `tcp.flags.syn==1 && tcp.flags.ack==0` |
| SYN-ACK | Respuesta del servidor al SYN. | Si es muy inferior a SYN, puede haber saturación, filtrado o pérdidas en establecimiento. | `tcp.flags.syn==1 && tcp.flags.ack==1` |
| ACK-only | ACK puros sin payload. | Ayuda a entender el overhead de control TCP frente a tráfico útil. | `tcp.flags.ack==1 && tcp.flags.syn==0 && tcp.flags.fin==0 && tcp.flags.reset==0 && tcp.len==0` |
| FIN | Cierres ordenados de conexión. | Valida que las sesiones terminan de forma limpia (comportamiento esperado). | `tcp.flags.fin==1` |
| RST | Resets TCP (cierre abrupto). | Señal de fallos/abortos; si sube, suele degradar éxito de handshake/aplicación. | `tcp.flags.reset==1` |

### 2) TCP ANOMALIAS

| Métrica | Qué significa | Para qué sirve | Campo/filtro tshark base |
|---|---|---|---|
| Retransmissions | Reenvíos TCP detectados. | Cuantifica pérdida/congestión efectiva; clave para separar problema de red vs cómputo TLS. | `tcp.analysis.retransmission` |
| Fast Retransmissions | Retransmisión rápida por DUP ACK. | Indica reacciones tempranas de TCP ante pérdida; útil para ver estrés de red. | `tcp.analysis.fast_retransmission` |
| Spurious Retransmissions | Retransmisiones innecesarias. | Puede revelar reordenación o diagnóstico excesivo de pérdida. | `tcp.analysis.spurious_retransmission` |
| Duplicate ACK | ACK duplicados. | Señal indirecta de pérdida/reordenación; contextualiza retransmisiones. | `tcp.analysis.duplicate_ack` |
| Out of order | Segmentos fuera de orden. | Ayuda a detectar desorden de entrega (path/network behavior). | `tcp.analysis.out_of_order` |
| Lost segments | Segmentos marcados como perdidos. | Aproxima severidad de problemas de transporte visibles en captura. | `tcp.analysis.lost_segment` |

### 3) TLS METRICAS

| Métrica | Qué significa | Para qué sirve | Campo/filtro tshark base |
|---|---|---|---|
| TLS handshake messages total | Total mensajes handshake TLS visibles. | Permite dimensionar actividad de negociación TLS frente al total de tráfico. | `tls.handshake` |
| TLS alerts | Alertas TLS. | Detecta errores de negociación/autenticación y fallos de sesión. | `tls.alert_message` |
| ClientHello count | Nº de ClientHello. | Base de intentos de conexión TLS (denominador de éxito). | `tls.handshake.type==1` |
| ServerHello count | Nº de ServerHello. | Mide respuestas TLS del servidor a intentos del cliente. | `tls.handshake.type==2` |
| EncryptedExtensions count | Nº de EncryptedExtensions visibles. | Evidencia avance de handshake TLS 1.3 cuando es decodificable. | `tls.handshake.type==8` |
| Certificate count | Nº de certificados visibles. | Útil para inspeccionar fase de autenticación/cadena cert. | `tls.handshake.type==11` |
| CertificateVerify count | Nº de CertificateVerify visibles. | Confirma progreso de validación criptográfica en handshake. | `tls.handshake.type==15` |
| Finished count | Nº de Finished visibles. | Sirve para fin “estricto” de handshake; puede faltar por cifrado/visibilidad de dissector. | `tls.handshake.type==20` |

### 4) VOLUMEN / SEGMENTACION

| Métrica | Qué significa | Para qué sirve | Campo/filtro tshark base |
|---|---|---|---|
| Packets total | Paquetes totales del filtro. | Tamaño bruto del experimento para normalizar comparativas. | `BASE_FILTER` |
| Bytes total | Bytes totales del filtro. | Magnitud total del tráfico intercambiado en la prueba. | `frame.len` sobre `BASE_FILTER` |
| ClientHello packets | Paquetes que llevan CH. | Indica si CH suele ir en 1 paquete o fragmentado. | `tls.handshake.type==1` |
| ServerHello packets | Paquetes que llevan SH. | Muestra coste de segmentación del SH (relevante en híbrido). | `tls.handshake.type==2` |
| ClientHello frame bytes | Bytes de trama asociados a CH. | Coste total en cable (incluye cabeceras L2/L3/L4). | `frame.len` con `tls.handshake.type==1` |
| ServerHello frame bytes | Bytes de trama asociados a SH. | Permite comparar expansión visible de respuesta servidor. | `frame.len` con `tls.handshake.type==2` |
| ClientHello tcp payload bytes | Payload TCP asociado a CH. | Tamaño útil de datos sin cabeceras para comparativas criptográficas. | `tcp.len` con `tls.handshake.type==1` |
| ServerHello tcp payload bytes | Payload TCP asociado a SH. | Base para ratio de expansión ServerHello/ClientHello. | `tcp.len` con `tls.handshake.type==2` |
| Max TCP payload bytes | Máximo `tcp.len`. | Detecta picos de payload y posible presión sobre MSS. | `tcp.len>0` + campo `tcp.len` |
| Max IP packet bytes (ip.len) | Máximo tamaño IP L3. | Verifica proximidad/exceso respecto a MTU asumida. | campo `ip.len` |
| Max Ethernet frame bytes (frame.len) | Máximo tamaño L2. | Ayuda a validar overhead total y límites de enlace. | campo `frame.len` |
| TCP MSS client advertised | MSS anunciado por cliente. | Define límite de payload anunciado por cliente al iniciar. | `tcp.options.mss_val` en `SYN` |
| TCP MSS server advertised | MSS anunciado por servidor. | Límite de payload anunciado por servidor en respuesta. | `tcp.options.mss_val` en `SYN-ACK` |
| TCP MSS negotiated (approx) | MSS efectivo aproximado. | Referencia para checks de segmentos “sobredimensionados”. | derivado de MSS cliente/servidor |
| MTU assumed bytes (L3) | MTU de referencia usada (1500). | Umbral operativo para validar oversize a nivel IP. | constante del script |
| Packets exceeding MTU assumed | Paquetes `ip.len > MTU`. | Detecta tráfico potencialmente problemático por tamaño IP. | `ip.len` comparado con MTU |
| Packets exceeding MTU client->server | Exceso MTU en c→s. | Localiza si el exceso lo introduce cliente. | `ip.src==PRIMARY_CLIENT_IP && ip.len>MTU` |
| Packets exceeding MTU server->client | Exceso MTU en s→c. | Localiza si el exceso lo introduce servidor. | `ip.dst==PRIMARY_CLIENT_IP && ip.len>MTU` |
| TCP segments exceeding negotiated MSS | `tcp.len > MSS`. | Evalúa incumplimiento práctico del MSS negociado. | `tcp.len` comparado con MSS negociado |
| IP packets exceeding negotiated MSS estimate | `ip.len > MSS+40`. | Proxy simple para detectar superación de MSS con cabeceras IP/TCP. | `ip.len` comparado con `MSS+40` |
| TCP segments > MSS client->server | Exceso MSS en c→s. | Atribuye excedentes MSS al sentido cliente→servidor. | `ip.src==PRIMARY_CLIENT_IP && tcp.len>MSS` |
| TCP segments > MSS server->client | Exceso MSS en s→c. | Atribuye excedentes MSS al sentido servidor→cliente. | `ip.dst==PRIMARY_CLIENT_IP && tcp.len>MSS` |
| MSS unique values in SYN (client) | MSS distintos en SYN cliente. | Detecta variación de configuración de cliente/red. | `tcp.options.mss_val` en `SYN` (set único) |
| MSS unique values in SYN-ACK (server) | MSS distintos en SYN-ACK servidor. | Detecta variación de configuración del servidor/red. | `tcp.options.mss_val` en `SYN-ACK` (set único) |
| IP fragmented packets count | Paquetes fragmentados IP. | Evidencia directa de fragmentación (coste/latencia potencial). | `ip.flags.mf==1 || ip.frag_offset>0` |
| TCP near-MSS window count | Segmentos cerca del MSS. | Indica si el tráfico opera cerca del máximo útil de segmento. | `tcp.len` en ventana `[MSS-60,MSS]` |
| ClientHello streams | Streams con CH. | Cuenta conexiones TLS distintas iniciadas (por `tcp.stream`). | campo `tcp.stream` con `tls.handshake.type==1` |
| ClientHello packets per stream avg | Paquetes CH por stream. | Resume fragmentación media de CH por conexión. | conteo por `tcp.stream` de `tls.handshake.type==1` |
| ServerHello streams | Streams con SH. | Cuenta conexiones con respuesta del servidor. | campo `tcp.stream` con `tls.handshake.type==2` |
| ServerHello packets per stream avg | Paquetes SH por stream. | Resume fragmentación media de SH por conexión. | conteo por `tcp.stream` de `tls.handshake.type==2` |

### 5) RTT y latencias TLS/TCP

| Métrica | Qué significa | Para qué sirve | Campo/filtro tshark base |
|---|---|---|---|
| TCP ACK RTT avg/max/p50/p95/p99 | RTT observado en ACK. | Controla latencia de red base para no confundirla con coste criptográfico. | campo `tcp.analysis.ack_rtt` |
| Lat TCP SYN -> SYN-ACK | Latencia apertura TCP. | Mide tiempo de respuesta inicial del servidor/red en conexión TCP. | `frame.time_epoch` entre SYN y SYN-ACK |
| Lat TCP SYN-ACK -> ACK | Cierre 3-way handshake. | Captura reacción del cliente tras recibir SYN-ACK. | `frame.time_epoch` entre SYN-ACK y ACK |
| Lat TLS CH -> SH (primary) | CH→SH del stream principal. | Referencia puntual del primer stream observado (diagnóstico rápido). | `frame.time_epoch` entre `tls.handshake.type==1` y `==2` |
| Lat TLS CH -> SH avg (all streams) | Media CH→SH sobre población. | Resume comportamiento medio de establecimiento TLS bajo carga. | agregado por `tcp.stream` (CH→SH) |
| Lat TLS CH -> SH p50/p95/p99 | Percentiles CH→SH globales. | Cuantifica variabilidad/cola de latencia, clave para SLA. | agregado por `tcp.stream` (CH→SH) + percentiles |
| Lat TLS CH -> SH samples (N) | Nº streams usados. | Indica robustez estadística de percentiles CH→SH. | contador de streams válidos CH→SH |
| Lat TLS SH -> Finished | SH→Finished (si visible). | Ayuda a descomponer coste final del handshake cuando Finished es visible. | `frame.time_epoch` entre SH y `tls.handshake.type==20` |
| Lat TLS Finished -> AppData | Finished→AppData. | Estima transición handshake→datos de aplicación. | `frame.time_epoch` entre Finished y `tls.app_data` / `content_type==23` |

### 6) TIEMPO APROX HANDSHAKE DESDE PCAP

| Métrica | Qué significa | Para qué sirve | Campo/filtro tshark base |
|---|---|---|---|
| Handshake start/end epoch | Timestamps de inicio/fin. | Permite auditar visualmente dónde cae el handshake en la captura. | `frame.time_epoch` de CH y fin heurístico |
| Handshake duration ms (primary) | Duración puntual stream principal. | Medida rápida por stream principal para diagnóstico manual. | diferencia de epochs CH→fin heurístico (stream principal) |
| Handshake duration avg ms (sampled) | Media sobre streams válidos. | Resume coste promedio de establecimiento según heurística aplicada. | agregado por `tcp.stream` con fin heurístico |
| Handshake duration p50/p95/p99 | Percentiles de duración heurística. | Captura dispersión y cola de duración de handshake bajo carga. | percentiles sobre duraciones por stream |
| Handshake duration samples (N) | Nº muestras usadas. | Permite validar si los percentiles son estadísticamente fiables. | contador `HS_N` del agregador |
| Handshake duration sample threshold | Umbral mínimo N para “ok”. | Define criterio operativo para marcar calidad de percentiles. | variable `HANDSHAKE_MIN_SAMPLES` |
| Handshake duration percentile quality | `ok` / `insufficient_samples` / `no_samples`. | Semáforo de confianza para decidir si usar esa métrica en comparativas. | derivado de `HS_N` y umbral |
| Handshake fallback max gap ms | Umbral de fallback AppData. | Evita incluir AppData tardío que no represente fin de handshake. | variable `HS_APPDATA_FALLBACK_MAX_MS` |
| Handshake streams with CH | Streams con CH detectado. | Denominador de tasa de éxito de handshake. | conteo streams con `tls.handshake.type==1` |
| Handshake streams complete | Streams CH+SH+fin heurístico. | Numerador de éxito; aproxima handshakes completos observables. | stream con CH + SH + (Finished o AppData válido) |
| Handshake success rate (%) | `complete / CH * 100`. | Mide robustez real de establecimiento bajo carga/estrés. | derivado `HS_COMPLETE/CH_TOTAL` |
| Handshake throughput global (hs/s) | Completados por segundo global. | KPI de capacidad efectiva del sistema en la prueba. | completados por bucket temporal (1s) |
| Handshake throughput p50/p95/p99 | Throughput por ventanas. | Cuantifica estabilidad temporal y cola de rendimiento. | percentiles sobre buckets de throughput |
| Handshake throughput peak | Pico de hs/s. | Muestra techo instantáneo de capacidad alcanzado. | máximo de buckets de throughput |
| Handshake throughput ventanas usadas | Nº ventanas para throughput. | Contextualiza representatividad temporal de percentiles throughput. | número de buckets temporales |
| Crypto cost ratio (SH/CH) | `serverhello_tcp_bytes / clienthello_tcp_bytes`. | Permite evidenciar expansión de mensaje (muy útil en comparativa híbrido). | derivado de `tcp.len` en SH/CH |
| TLS hello bytes por conexión | `(CH+SH bytes)/conexiones`. | Resume overhead de señalización TLS por conexión. | derivado de bytes CH/SH y count CH |
| TLS hello bytes por conexión p50 | Percentil 50 de `(CH+SH bytes)` por stream/conexión válida. | Mide el coste típico por conexión evitando sesgo de outliers. | agregado por `tcp.stream` con `tls.handshake.type==1/2` + percentil p50 |
| Red-vs-CPU ratio cliente | `handshake_ms_avg / cpu_client_avg`. | Proxy rápido para ver si latencia crece con carga cliente. | derivado de handshake avg + `pqc_client_cpu_avg` |
| Red-vs-CPU ratio servidor | `handshake_ms_avg / cpu_server_avg`. | Proxy rápido para ver influencia de cómputo del servidor en latencia. | derivado de handshake avg + `pqc_server_cpu_avg` |

### 7) RECURSOS CPU/MEM

| Métrica | Qué significa | Para qué sirve | Campo/fuente base |
|---|---|---|---|
| Resource summary/raw csv present | Si existen ficheros de recursos. | Verifica disponibilidad de contexto de recursos para correlacionar red y CPU/MEM. | `results/${RUN_ID}_resource_summary.txt`, `results/${RUN_ID}_docker_stats.csv` |
| pqc_clients CPU/MEM avg/max | Recursos agregados de clientes. | Ayuda a explicar presión de clientes sobre latencia y estabilidad de throughput. | parsing de líneas `pqc_client*` en summary |
| pqc_server CPU/MEM avg/max | Recursos del servidor. | Principal indicador de cuello de cómputo bajo carga TLS/PQC. | parsing de línea `pqc_server` en summary |
| pqc_monitor CPU/MEM avg/max | Recursos de monitorización. | Controla que la observabilidad no esté introduciendo overhead relevante. | parsing de línea `pqc_monitor` en summary |

---

## Tabla Top métricas para comparativa Clásico vs Híbrido

| KPI | Prioridad | Qué compara | Cómo interpretar | Correspondencia en tablas superiores (sección/etiqueta TXT) |
|---|---|---|---|---|
| `lat_tls_ch_to_sh_p50_ms` | Alta | Latencia típica establecimiento TLS | Si sube en híbrido, hay coste medio adicional. | Sección **5) RTT y latencias TLS/TCP** → `Lat TLS CH -> SH p50/p95/p99`. |
| `lat_tls_ch_to_sh_p95_ms` | Alta | Cola de latencia bajo carga | Sensible a saturación/colas. | Sección **5) RTT y latencias TLS/TCP** → `Lat TLS CH -> SH p50/p95/p99`. |
| `lat_tls_ch_to_sh_p99_ms` | Alta | Peor cola de latencia | Útil para SLA/estrés. | Sección **5) RTT y latencias TLS/TCP** → `Lat TLS CH -> SH p50/p95/p99`. |
| `lat_tls_ch_to_sh_n` | Alta (control) | Tamaño muestral | Evitar comparar percentiles con N bajo. | Sección **5) RTT y latencias TLS/TCP** → `Lat TLS CH -> SH samples (N)`. |
| `handshake_throughput_global_hsps` | Alta | Capacidad efectiva | Handshakes completos por segundo. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `Handshake throughput global (hs/s)`. |
| `handshake_throughput_p95_hsps` | Alta | Estabilidad temporal de capacidad | Si cae en híbrido, peor regularidad. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `Handshake throughput p50/p95/p99`. |
| `handshake_throughput_peak_hsps` | Media | Pico instantáneo | Techo puntual de capacidad. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `Handshake throughput peak`. |
| `handshake_success_rate_pct` | Alta | Robustez en estrés | Impacto de fiabilidad. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `Handshake success rate (%)`. |
| `hello_payload_expansion_ratio` | Alta | Expansión SH/CH | Sobrehead de mensaje híbrido/PQC. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `Crypto cost ratio (SH/CH)`. |
| `tls_hs_bytes_per_connection` | Alta | Coste medio de bytes por conexión | Overhead medio de señalización TLS. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `TLS hello bytes por conexión`. |
| `tls_hs_bytes_per_connection_p50` | Alta | Coste típico de bytes por conexión | Reduce impacto de outliers frente a la media. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `TLS hello bytes por conexión p50`. |
| `pqc_server_cpu_avg/max` | Alta | Coste computacional servidor | Si sube CPU + latencia, cuello cómputo. | Sección **7) RECURSOS CPU/MEM** → `pqc_server CPU/MEM avg/max`. |
| `pqc_client_cpu_avg/max` | Media | Coste computacional cliente | Complementa impacto extremo. | Sección **7) RECURSOS CPU/MEM** → `pqc_clients CPU/MEM avg/max`. |
| `tcp_ack_rtt_p95_ms` | Alta (control) | Condición de red base | Si RTT similar, diferencias no son red. | Sección **5) RTT y latencias TLS/TCP** → `TCP ACK RTT avg/max/p50/p95/p99`. |
| `retransmissions` | Media (control) | Ruido/pérdida transporte | Evitar atribuir todo a PQC. | Sección **2) TCP ANOMALIAS** → `Retransmissions`. |

### Métricas útiles con cautela

| Métrica | Cuándo usar | Correspondencia en tablas superiores (sección/etiqueta TXT) |
|---|---|---|
| `handshake_duration_p50/p95/p99` | Solo con `handshake_duration_quality = ok` y `N` suficiente. | Sección **6) TIEMPO APROX HANDSHAKE DESDE PCAP** → `Handshake duration p50/p95/p99` + `Handshake duration percentile quality`. |
| `lat_tls_ch_to_sh_ms (primary stream)` | Diagnóstico puntual, no KPI principal masivo. | Sección **5) RTT y latencias TLS/TCP** → `Lat TLS CH -> SH (primary)`. |
| `lat_tls_sh_to_fin_ms`, `lat_tls_fin_to_appdata_ms` | Pueden quedar vacías por visibilidad TLS. | Sección **5) RTT y latencias TLS/TCP** → `Lat TLS SH -> Finished` y `Lat TLS Finished -> AppData`. |

### Reglas de comparativa entre campañas

1. Mantener fijo `HS_APPDATA_FALLBACK_MAX_MS` para comparabilidad.
2. Exigir `handshake_duration_quality=ok` antes de usar percentiles handshake heurístico.
3. Si no hay calidad suficiente, usar como KPIs principales: `lat_tls_ch_to_sh_*`, throughput, success rate y CPU.
