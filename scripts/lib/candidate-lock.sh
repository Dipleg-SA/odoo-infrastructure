#!/usr/bin/env bash
# Exclusión compartida para candidatos
# Bash y Python bloquean los mismos archivos mediante fcntl.
set -euo pipefail

# Ruta del bloqueo
# En el host vive bajo runtime/control/state; en el receptor usa el montaje equivalente.
candidate_lock_path() {
  local tipo="$1" clave="$2" raiz script_dir proyecto
  case "$tipo" in
    entorno)
      case "$clave" in desarrollo|staging|produccion) ;; *) return 2 ;; esac
      ;;
    repositorio)
      [[ "$clave" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 2
      ;;
    *) return 2 ;;
  esac

  proyecto="${CANDIDATE_LOCK_PROJECT:-${COMPOSE_PROJECT_NAME:-}}"
  [[ "$proyecto" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    printf '%s\n' 'candidate-lock: falta un COMPOSE_PROJECT_NAME válido' >&2
    return 2
  }

  if [[ -n "${ADDONS_STATE_DIR:-}" ]]; then
    raiz="$ADDONS_STATE_DIR"
  else
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 2
    raiz="$(cd -- "$script_dir/../.." && pwd -P)/runtime/control/state"
  fi
  raiz="$raiz/locks/$proyecto"
  if [[ "$tipo" == repositorio ]]; then
    raiz="$raiz/locks/repos"
  else
    raiz="$raiz/locks"
  fi
  mkdir -p "$raiz"
  printf '%s/%s.lock' "$raiz" "$clave"
}

# Ejecución bajo bloqueo
# El proceso hijo termina antes de liberar el descriptor y el archivo.
candidate_lock_execute() {
  local ruta="$1"
  shift
  [[ $# -gt 0 ]] || { printf '%s\n' 'candidate-lock: falta el comando' >&2; return 2; }
  python3 - "$ruta" "$@" <<'PY'
import fcntl
import os
import subprocess
import sys

lock_path, *command = sys.argv[1:]
os.makedirs(os.path.dirname(lock_path), exist_ok=True)
flags = os.O_CREAT | os.O_RDWR
if hasattr(os, "O_NOFOLLOW"):
    flags |= os.O_NOFOLLOW
descriptor = os.open(lock_path, flags, 0o600)
with os.fdopen(descriptor, "a+b") as lock_file:
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    result = subprocess.run(command, close_fds=True)
sys.exit(result.returncode)
PY
}

# Bloqueo por entorno
# Serializa la publicación de candidatos y la fotografía que los consume.
candidate_lock_run() {
  local entorno="$1" ruta
  shift
  [[ "${1:-}" == -- ]] || { printf '%s\n' 'Uso: candidate_lock_run <entorno> -- <comando> [argumentos...]' >&2; return 2; }
  shift
  ruta="$(candidate_lock_path entorno "$entorno")" || return 2
  candidate_lock_execute "$ruta" "$@"
}

# Bloqueo por repositorio
# Evita que dos entornos modifiquen a la vez las referencias del mismo clon bare.
candidate_lock_repo_run() {
  local dominio="$1" ruta
  shift
  [[ "${1:-}" == -- ]] || { printf '%s\n' 'Uso: candidate_lock_repo_run <dominio> -- <comando> [argumentos...]' >&2; return 2; }
  shift
  ruta="$(candidate_lock_path repositorio "$dominio")" || return 2
  candidate_lock_execute "$ruta" "$@"
}

# Interfaz de comandos
# Permite probar y reutilizar el mismo bloqueo desde otros entrypoints.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    run)
      shift
      candidate_lock_run "$@"
      ;;
    repo)
      shift
      candidate_lock_repo_run "$@"
      ;;
    *)
      printf 'Uso: %s run <entorno>|repo <dominio> -- <comando> [argumentos...]\n' "$(basename "$0")" >&2
      exit 2
      ;;
  esac
fi
