# Medición de CPU y memoria en pruebas de peticiones TLS

## Enfoque recomendado (práctico)
1. Medir recursos a nivel de contenedor con `docker stats` durante toda la prueba.
2. Guardar muestras periódicas en CSV para análisis posterior.
3. Ejecutar el generador de carga TLS (single, ráfaga, batch) en paralelo.
4. Calcular por contenedor: CPU% promedio/máximo y MEM% promedio/máximo.
5. Comparar resultados entre escenarios (`classic_*` vs `hybrid_*`).

## Script incluido
Se añadió `measure_tls_resources.sh` (en raíz y en `scripts/`) para automatizar esto.

### Casos de uso
- **Medir una prueba puntual**:
  ```bash
  ./scripts/measure_tls_resources.sh classic_cpu 1 -- ./scripts/run_client_once.sh classic_cpu
  ```

- **Medir una ráfaga de peticiones**:
  ```bash
  ./scripts/measure_tls_resources.sh rafaga_cpu 1 -- ./scripts/run_client_once_rafaga.sh rafaga_cpu
  ```

- **Medir línea base en reposo**:
  ```bash
  ./scripts/measure_tls_resources.sh baseline_idle 1 30
  ```

## Artefactos generados
- `results/<RUN_ID>_docker_stats.csv`: muestras crudas por timestamp y contenedor.
- `results/<RUN_ID>_resource_summary.txt`: resumen de CPU/MEM (avg/max).

## Recomendaciones metodológicas
- Repetir cada escenario al menos 5-10 veces y usar mediana + p95.
- Mantener mismo intervalo de muestreo (ej. 1s) en todas las campañas.
- Ejecutar primero baseline y restarlo para estimar sobrecoste TLS real.
- Separar pruebas clásicas e híbridas con `RUN_ID` consistentes.
- Guardar también métricas de red/handshake para correlacionar coste-rendimiento.
