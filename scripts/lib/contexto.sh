#!/usr/bin/env bash
# Contexto del runtime
# Valida ENTORNO, carga sus variables y centraliza las llamadas a Compose.

# Validación y carga
# Calcula rutas absolutas desde el checkout y carga el archivo privado del entorno.
contexto_iniciar() {
  local entorno="${ENTORNO:-}" raiz script_dir ruta_runtime archivo_compose archivo_env allexport_activo=0

  case "$entorno" in
    desarrollo|staging|produccion) ;;
    *)
      printf 'ENTORNO debe ser desarrollo, staging o produccion\n' >&2
      return 2
      ;;
  esac

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 2
  raiz="$(cd -- "$script_dir/../.." && pwd -P)" || return 2
  ruta_runtime="$raiz/runtime/$entorno"
  archivo_compose="$ruta_runtime/compose.yaml"
  archivo_env="$ruta_runtime/compose.env"

  if [[ "${CONTEXTO_ENTORNO:-}" == "$entorno" && "${RUNTIME_DIR:-}" == "$ruta_runtime" && -f "$archivo_compose" && -f "$archivo_env" ]]; then
    return 0
  fi

  if [[ ! -f "$archivo_compose" || ! -f "$archivo_env" ]]; then
    printf 'Falta la composición o runtime/%s/compose.env; copiar la plantilla compose.env.example\n' "$entorno" >&2
    return 2
  fi

  case "$-" in *a*) allexport_activo=1 ;; esac
  set -a
  if ! . "$archivo_env"; then
    [[ "$allexport_activo" -eq 1 ]] || set +a
    printf 'No se pudo cargar runtime/%s/compose.env\n' "$entorno" >&2
    return 2
  fi
  [[ "$allexport_activo" -eq 1 ]] || set +a

  ENTORNO="$entorno"
  RUNTIME_DIR="$ruta_runtime"
  RUNTIME_ROOT="$ruta_runtime"
  RUNTIME_COMPOSE_FILE="$archivo_compose"
  RUNTIME_ENV_FILE="$archivo_env"
  RUNTIME_CONFIG_DIR="$ruta_runtime/config"
  RUNTIME_SECRETS_DIR="$ruta_runtime/secrets"
  RUNTIME_STATE_DIR="$ruta_runtime/state"
  export ENTORNO RUNTIME_DIR RUNTIME_ROOT RUNTIME_COMPOSE_FILE RUNTIME_ENV_FILE
  export RUNTIME_CONFIG_DIR RUNTIME_SECRETS_DIR RUNTIME_STATE_DIR
  CONTEXTO_ENTORNO="$entorno"
  export CONTEXTO_ENTORNO
}

# Línea mayor de Odoo
# Los candidatos y el receptor derivan las ramas de integración del Dockerfile.
contexto_odoo_version() {
  local script_dir raiz
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 2
  raiz="$(cd -- "$script_dir/../.." && pwd -P)" || return 2
  sed -nE 's/^[[:space:]]*FROM[[:space:]]+odoo:([0-9]+([.][0-9]+)*).*/\1/p' \
    "$raiz/stacks/odoo/image/Dockerfile" | head -1
}

# Invocación de Compose
# Siempre pasa el compose.yaml y compose.env del entorno ya validado.
contexto_compose() {
  contexto_iniciar || return $?
  docker compose --env-file "$RUNTIME_ENV_FILE" -f "$RUNTIME_COMPOSE_FILE" "$@"
}

# Perfiles de Compose
# Agrega perfiles a los del runtime sin reemplazar los ya declarados.
contexto_compose_perfiles() {
  local perfiles="$1"
  shift
  contexto_iniciar || return $?
  if [[ -n "${COMPOSE_PROFILES:-}" ]]; then
    COMPOSE_PROFILES="$perfiles,$COMPOSE_PROFILES"
  else
    COMPOSE_PROFILES="$perfiles"
  fi
  export COMPOSE_PROFILES
  contexto_compose "$@"
}

# Entrada de línea de comandos
# Permite que Make y los scripts usen el mismo wrapper sin duplicar flags.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    validar)
      contexto_iniciar
      ;;
    compose)
      shift
      contexto_compose "$@"
      ;;
    compose-perfiles)
      shift
      [[ $# -ge 2 ]] || { printf 'Uso: %s compose-perfiles <perfiles> <argumentos de docker compose>\n' "$0" >&2; exit 2; }
      contexto_compose_perfiles "$@"
      ;;
    *)
      printf 'Uso: ENTORNO=<desarrollo|staging|produccion> %s <validar|compose|compose-perfiles> ...\n' "$0" >&2
      exit 2
      ;;
  esac
fi
