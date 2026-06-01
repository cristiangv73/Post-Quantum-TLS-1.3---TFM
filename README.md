# Post-Quantum-TLS-1.3

Laboratorio reproducible para evaluar **TLS 1.3 clásico** frente a **TLS 1.3 híbrido post-cuántico** usando Docker, OpenSSL y `oqs-provider`.

## Resumen ejecutivo

Este repositorio permite medir, comparar y documentar el comportamiento de handshake TLS en dos modos:

- **Clásico:** `X25519`
- **Híbrido PQ:** `X25519MLKEM768`

El objetivo es cuantificar impacto en latencia, volumen de tráfico, estabilidad TCP y consumo de recursos, bajo carga simple y en ráfaga multicliente.

## Objetivos de análisis

- Medir duración del handshake TLS 1.3.
- Analizar tamaño/número de paquetes y mensajes TLS.
- Identificar eventos TCP relevantes (retransmisiones, DupACK, Out-of-Order, resets).
- Medir CPU/MEM por contenedor durante pruebas.
- Comparar escenarios con perfiles de llegada (**Poisson+jitter** vs **stress**) y perfiles de red (**P0..P3**).

## Arquitectura del laboratorio

<img width="521" height="786" alt="ESQUEMA_PQC_definitivo" src="https://github.com/user-attachments/assets/ce8747e2-ba88-4ace-90bd-4c21ccdc3ea4" />

Topología dockerizada cliente-monitor-servidor:

- **Clientes (`pqc_client*`)** en `client_net` (`172.20.0.0/24`).
- **Servidor (`pqc_server`)** en `server_net` (`192.168.0.0/24`), puerto TLS `4433`.
- **Monitor/router (`pqc_monitor`)** conectado a ambas redes:
  - reenvía tráfico (`ip_forward=1`),
  - permite captura de paquetes,
  - aplica degradación de red (`tc netem`).

El script `scripts/setup_rutas.sh` fuerza el paso cliente↔servidor por `pqc_monitor` para garantizar observabilidad y reproducibilidad.

## Estructura del repositorio

- `compose.yaml`: servicios, redes, capacidades y volúmenes.
- `client/`, `server/`, `monitor/`: imágenes de ejecución.
- `configs/openssl-oqs.cnf`: configuración OpenSSL + OQS provider.
- `certs/`: CA y certificados del laboratorio (generados localmente con `scripts/gen-certs.sh`).
- `scripts/`: automatización de ejecución, captura y extracción.
- `pcaps/`: capturas de red.
- `results/`: artefactos y métricas procesadas.
- `workflow.md`: guía operacional completa.
- `analisis_scripts.md`: análisis funcional de todos los scripts.

### Función de cada carpeta/archivo principal

- `compose.yaml`: define la topología de contenedores, redes y volúmenes del laboratorio.
- `client/`: imagen base y punto de entrada para ejecutar clientes TLS de prueba.
- `server/`: imagen base y utilidades para levantar el servidor TLS 1.3 (clásico/híbrido).
- `monitor/`: contenedor puente para captura (`tcpdump`) y degradación de red (`tc netem`).
- `configs/`: configuración de OpenSSL y providers PQ para escenarios híbridos.
- `certs/`: almacén local de CA/certificados de laboratorio (no versionar claves privadas).
- `scripts/`: automatización de campañas, ejecución de pruebas, extracción y resumen de métricas.
- `pcaps/`: capturas de tráfico de cada corrida (`RUN_ID`) para análisis de red.
- `results/`: salidas procesadas (TXT/CSV) y resúmenes para comparación estadística.
- `workflow.md`: procedimiento operativo estándar reproducible paso a paso.
- `analisis_scripts.md`: inventario y explicación funcional detallada de scripts.

## Inicio rápido

```bash
./scripts/gen-certs.sh
docker compose up -d --build
./scripts/setup_rutas.sh
```

Prueba clásica básica:

```bash
./scripts/run_client_once.sh classic_001
./scripts/extract_metrics3.sh classic_001
```

Prueba híbrida básica:

```bash
./scripts/run_client_once_hibrido.sh hybrid_001
./scripts/extract_metrics3.sh hybrid_001
```

## Flujo recomendado de evaluación

1. Levantar entorno y rutas.
2. Lanzar servidor en modo clásico o híbrido.
3. Capturar tráfico en `pqc_monitor`.
4. Ejecutar caso (simple o ráfaga).
5. Ejecutar **`scripts/extract_metrics3.sh`** (script más completo).
6. Consolidar resultados para comparación estadística.

## Script de métricas recomendado

Aunque existen `extract_metrics.sh` y `extract_metrics2.sh`, el repositorio recomienda usar:

- **`scripts/extract_metrics3.sh`** → extracción más completa (TXT + CSV + integración de recursos cuando existe `*_resource_summary.txt`).

## Buenas prácticas para publicación/reproducibilidad

- Usar `RUN_ID` consistente (`classic_*`, `hybrid_*`).
- Mantener constantes `CLIENTS`, `TOTAL_CONN`, perfil de red y perfil de llegada al comparar escenarios.
- Ejecutar múltiples repeticiones y reportar mediana/p95.
- Versionar resultados procesados (CSV/TXT), evitando subir capturas masivas no necesarias.


## Estructura de la campaña experimental

La campaña experimental se ha construido a partir del dataset generado por el laboratorio reproducible.

La hoja **Datos_limpios** del Excel contiene un total de **640 ejecuciones experimentales**, distribuidas de forma equilibrada entre los dos escenarios criptográficos evaluados:

- **Classic:** TLS 1.3 clásico con intercambio de claves `X25519`.
- **Hybrid:** TLS 1.3 híbrido con intercambio `X25519MLKEM768`.

La campaña combina cuatro perfiles de red, cuatro perfiles de carga, cuatro volúmenes de conexión y cinco repeticiones por combinación:

- **2 escenarios × 4 perfiles de red × 4 perfiles de carga × 4 volúmenes × 5 repeticiones = 640 ejecuciones**.

En cada una de estas 640 ejecuciones, se miden **103 métricas por ejecución**, dando un total de **65.920 datos** a analizar.

Los resultados se presentan desglosados en tres dimensiones:

- **Perfil de red:** `P0`, `P1`, `P2`, `P3`.
- **Perfil de carga:** `soft`, `balanced`, `aggressive`, `stress`.
- **Número de conexiones:** `6`, `50`, `300`, `1002`.

De tal forma, que la nomenclatura de cada ejecución sigue el siquiente patron:

**[modelo]_[perfil_de_Red]_[perfil_carga]_[num_conexiones]_[num_repeticion].csv**

Ejemplos: classic_p0_balanced_c50_003, hybrid_p2_aggressive_c1002_005...

Las métricas analizadas permiten estudiar el impacto del modo híbrido desde una perspectiva multicapa: volumen transmitido, paquetización, latencia TLS, throughput, consumo de CPU y comportamiento TCP.

Se adjunta Pipeline del laboratorio:

<img width="1536" height="1024" alt="Pipeline_v3" src="https://github.com/user-attachments/assets/17aa241e-9971-479c-8dc2-fad3d165cba3" />



## Alcance

Proyecto orientado a investigación aplicada y validación experimental, no a despliegues de producción.
