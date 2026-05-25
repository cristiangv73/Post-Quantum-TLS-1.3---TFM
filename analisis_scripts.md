# Análisis funcional de scripts del repositorio

Este documento describe el funcionamiento de **todos los scripts `.sh`** del proyecto, agrupados por responsabilidad operativa.

---

## 1) Scripts de infraestructura y arranque de contenedores

### `client/entrypoint.sh`
- Configura ruta desde la red cliente hacia `server_net` vía `pqc_monitor`.
- Imprime tabla de rutas para verificación.
- Mantiene el contenedor activo para ejecución de pruebas.

### `server/entrypoint.sh`
- Configura ruta desde la red servidor hacia `client_net` vía `pqc_monitor`.
- Imprime tabla de rutas.
- Mantiene el contenedor activo.

### `monitor/entrypoint.sh`
- Habilita `ip_forward=1` para actuar como router.
- Muestra estado de forwarding, interfaces y rutas.
- Deja el contenedor en ejecución continua.

### `scripts/setup_rutas.sh`
- Refuerza/normaliza rutas entre clientes y servidor.
- Detecta clientes `pqc_client*` y aplica ruta en cada uno.
- Garantiza que el tráfico TLS pase por el monitor para captura y control.

---

## 2) Scripts de preparación de entorno y red

### `scripts/gen-certs.sh`
- Genera CA local, clave/CSR de servidor y certificado firmado.
- Prepara material TLS para `openssl s_server/s_client`.
- Incluye extensiones SAN para uso de laboratorio.

### `scripts/aplicar_perfil.sh`
- Aplica perfiles `tc netem` predefinidos (`P0..P3`) en monitor.
- Limpia `qdisc` previos antes de aplicar nuevo perfil.
- Permite simular latencia/pérdida de red reproducible.

### `scripts/fix_permissions.sh`
- Normaliza permisos de `scripts/`, `pcaps/` y `results/`.
- Corrige problemas típicos tras ejecuciones con Docker/sudo.

### `scripts/fix_pcap_permissions.sh`
- Ajusta propietario/permisos de un pcap específico por `RUN_ID`.
- Útil cuando una captura queda como `root`.

---

## 3) Scripts de ejecución de clientes/servidor

### `scripts/run_server_once_hybrid.sh`
- Lanza servidor TLS 1.3 híbrido (`X25519MLKEM768`) en `pqc_server`.
- Carga providers `default` + `oqsprovider`.

### `scripts/run_client_once.sh`
- Ejecuta una conexión TLS 1.3 clásica (`X25519`).
- Guarda stdout/stderr en `results/` por `RUN_ID`.

### `scripts/run_client_once_hibrido.sh`
- Ejecuta una conexión TLS 1.3 híbrida (`X25519MLKEM768`).
- Guarda salida y errores por `RUN_ID`.

### `scripts/run_client_once_rafaga.sh`
- Ejecuta ráfaga clásica concurrente, distribuida en round-robin multicliente.
- Soporta perfiles de llegada (`poisson_jitter` o `stress`).

### `scripts/run_client_once_rafaga_hibrido.sh`
- Ejecuta ráfaga híbrida concurrente con mismo patrón round-robin.
- Diseñado para campañas de carga de mayor volumen.

### `scripts/run_classic_once.sh`
- Flujo clásico integrado: captura, ejecución cliente, copia de pcap y tiempos.
- Simplifica una corrida end-to-end única.

### `scripts/run_semimanual_workflow.sh`
- Guía semimanual por pasos interactivos.
- Coordina captura, ejecución de prueba y extracción.

---

## 4) Scripts de campañas y automatización por lotes

### `scripts/run_classic_batch.sh`
- Repite corridas clásicas `N` veces.
- Invoca ejecución y extracción por iteración.

### `scripts/run_campaign_batch.sh`
- Orquestador genérico de campañas por lotes.
- Estandariza nomenclatura de `RUN_ID` y secuencias.

### `scripts/run_campaign_batch_classic.sh`
- Variante especializada para campañas clásicas.
- Automatiza múltiples ejecuciones comparables.

### `scripts/run_campaign_batch_hybrid.sh`
- Variante especializada para campañas híbridas.
- Facilita barridos de escenario equivalentes al modo clásico.

### `scripts/run_conn_scaling_batch.sh`
- Ejecuta campañas variando volumen de conexiones.
- Útil para curvas de escalado y saturación.

### `scripts/run_poisson_vs_stress_batch.sh`
- Ejecuta matriz Poisson+jitter vs stress.
- Permite comparar carga realista vs carga límite de forma sistemática.

---

## 5) Scripts de captura, extracción y análisis

### `scripts/fetch_pcap.sh`
- Copia capturas desde `pqc_monitor` al host (`pcaps/`).
- Gestiona rutas/limpieza para evitar sobrescrituras erróneas.

### `scripts/extract_metrics.sh`
- Extractor base de métricas TCP/TLS desde pcap.
- Genera reporte TXT sencillo.

### `scripts/extract_metrics2.sh`
- Extractor extendido (TXT + CSV).
- Añade filtrado por flujo e indicadores adicionales.

### `scripts/extract_metrics3.sh` (**script recomendado**)
- Extractor más completo del repositorio.
- Integra métricas de red/TLS y, si existen, métricas de recursos (`*_resource_summary.txt`, `*_docker_stats.csv`).
- Produce salidas comparables para campañas con mayor densidad analítica.
- **Debe ser el script por defecto en el workflow de publicación.**

### `scripts/summarize_results.sh`
- Consolida corridas en CSV agregado para análisis rápido.
- Facilita comparación entre `RUN_ID` homogéneos.

### `scripts/measure_tls_resources.sh`
- Muestrea `docker stats` durante una prueba.
- Genera CSV temporal y resumen CPU/MEM por contenedor.
- Diseñado para ejecutarse envolviendo un comando de prueba.

---

## 6) Script de utilidades compartidas

### `scripts/client_utils.sh`
- Biblioteca de funciones comunes para scripts de cliente.
- Reduce duplicación de lógica operativa (selección/detección/soporte de ejecución).

---

## 7) Artefactos no operativos encontrados en `scripts/`

Se detectan dos archivos que no forman parte del flujo de automatización (`ssh-keygen -t ed25519 -C "..."` y su `.pub`). Se recomienda moverlos fuera de `scripts/` o documentarlos explícitamente como artefactos de claves.

---

## Recomendación final para publicación

Para documentación pública y uso por terceros:

1. Mantener `workflow.md` alineado con `extract_metrics3.sh` como extractor oficial.
2. Etiquetar `extract_metrics.sh` y `extract_metrics2.sh` como heredados/compatibilidad.
3. Mantener este inventario actualizado al añadir nuevos scripts.
