#!/usr/bin/env bash

# Utilidades para manejar escenarios con uno o varios contenedores cliente.
# Fuentes de verdad (prioridad):
#   1) variable de entorno CLIENTS (csv o espacios)
#   2) contenedores en ejecución que hagan match pqc_client(_N)
#   3) lista por defecto del laboratorio

DEFAULT_CLIENTS=(pqc_client pqc_client_2 pqc_client_3 pqc_client_4 pqc_client_5 pqc_client_6)

normalize_clients_input() {
  local raw="$1"
  echo "$raw" | tr ',' ' ' | xargs
}

is_known_client_name() {
  local name="$1"
  [[ "$name" =~ ^pqc_client(_[0-9]+)?$ ]]
}

clients_from_env() {
  local raw normalized c
  raw="${CLIENTS:-}"
  if [ -z "$raw" ]; then
    return 0
  fi

  normalized="$(normalize_clients_input "$raw")"
  for c in $normalized; do
    if is_known_client_name "$c"; then
      echo "$c"
    fi
  done
}

running_clients() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi

  docker ps --format '{{.Names}}' 2>/dev/null \
    | awk '/^pqc_client(_[0-9]+)?$/ {print $0}' \
    | sort -V
}

all_known_clients() {
  printf '%s\n' "${DEFAULT_CLIENTS[@]}"
}

resolve_clients() {
  local source_clients=""
  source_clients="$(clients_from_env || true)"

  if [ -n "$source_clients" ]; then
    echo "$source_clients"
    return 0
  fi

  source_clients="$(running_clients || true)"
  if [ -n "$source_clients" ]; then
    echo "$source_clients"
    return 0
  fi

  all_known_clients
}

first_resolved_client() {
  resolve_clients | head -n 1
}
