# Workflow operativo del laboratorio TLS 1.3 (clásico e híbrido PQ)

Este documento define el procedimiento estándar para ejecutar campañas comparables y reproducibles.

## 1) Preparación del entorno

```bash
./scripts/gen-certs.sh
docker compose up -d --build
./scripts/fix_permissions.sh
./scripts/setup_rutas.sh
```

Verificación mínima:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

Debe haber al menos `pqc_server`, `pqc_monitor` y uno o más `pqc_client*` en estado `Up`.

## 2) Selección del modo TLS del servidor

### Modo clásico (`X25519`)

```bash
docker exec -it pqc_server bash -lc '
openssl s_server \
  -accept 4433 \
  -cert /certs/server/server.crt \
  -key /certs/server/server.key \
  -CAfile /certs/ca/ca.crt \
  -tls1_3 \
  -groups X25519 \
  -www'
```

### Modo híbrido (`X25519MLKEM768`)

```bash
docker exec -it pqc_server bash -lc '
openssl s_server \
  -accept 4433 \
  -cert /certs/server/server.crt \
  -key /certs/server/server.key \
  -CAfile /certs/ca/ca.crt \
  -tls1_3 \
  -groups X25519MLKEM768 \
  -provider default \
  -provider oqsprovider \
  -www'
```

## 3) Captura de tráfico (obligatoria para análisis de red)

Iniciar captura antes de cada prueba:

```bash
docker exec -it pqc_monitor bash -lc 'tcpdump -i eth0 -n -s 0 port 4433 -w /pcaps/<RUN_ID>.pcap'
```

Al finalizar el caso, detener con `Ctrl+C`.

## 4) Ejecución de pruebas

### A. Handshake clásico único

```bash
./scripts/run_client_once.sh classic_001
```

### B. Ráfaga clásica (multicliente round-robin)

```bash
./scripts/run_client_once_rafaga.sh classic_rafaga_001
```

### C. Handshake híbrido único

```bash
./scripts/run_client_once_hibrido.sh hybrid_001
```

### D. Ráfaga híbrida (multicliente round-robin)

```bash
./scripts/run_client_once_rafaga_hibrido.sh hybrid_rafaga_001
```

## 5) Extracción de métricas (estándar del repositorio)

> **Norma del workflow:** usar `scripts/extract_metrics3.sh` como extractor principal, ya que es el más completo.

```bash
./scripts/extract_metrics3.sh <RUN_ID>
```

Salida típica:

- `results/<RUN_ID>_metrics.txt`
- `results/<RUN_ID>_metrics.csv`
- (si existe muestreo de recursos) enriquecimiento con métricas CPU/MEM agregadas.

### Extractores heredados (solo compatibilidad)

- `extract_metrics.sh`: base.
- `extract_metrics2.sh`: intermedio.
- `extract_metrics3.sh`: **recomendado y obligatorio en este workflow**.

## 6) Medición de recursos (recomendado para campañas)

Ejemplo de ráfaga clásica + muestreo `docker stats`:

```bash
CLIENTS="pqc_client,pqc_client_2,pqc_client_3,pqc_client_4,pqc_client_5,pqc_client_6" \
./scripts/measure_tls_resources.sh classic_poisson_001 0.2 -- \
bash -lc './scripts/run_client_once_rafaga.sh classic_poisson_001 1000; sleep 3'
```

Luego:

```bash
./scripts/extract_metrics3.sh classic_poisson_001
```

## 7) Perfiles de llegada y red (diseño experimental)

### Llegadas

- `ARRIVAL_PROFILE=poisson_jitter` (recomendado para realismo).
- `ARRIVAL_PROFILE=stress` (carga máxima simultánea).

### Degradación de red

```bash
./scripts/aplicar_perfil.sh P0
./scripts/aplicar_perfil.sh P1
./scripts/aplicar_perfil.sh P2
./scripts/aplicar_perfil.sh P3
```

## 8) Protocolo mínimo de comparación justa

Mantener constantes entre escenarios:

- conjunto de clientes (`CLIENTS`),
- número de conexiones (`TOTAL_CONN`),
- perfil de red (`P0..P3`),
- modo TLS del servidor,
- estrategia de captura.

Realizar al menos 5 repeticiones por escenario y comparar mediana/p95.

## 9) Cierre

```bash
docker compose down
```

Si se desea limpieza total:

```bash
docker compose down -v
```
