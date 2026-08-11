#!/usr/bin/env bash
# Addons por bind-mount. sync reconstruye/actualiza el árbol, status
# imprime el estado de cada worktree. Sin dependencias fuera de git.
set -euo pipefail
shopt -s nullglob

cd "$(dirname "$0")/.."

MANIFEST="config/odoo/addons.txt"
BARE_DIR="addons/.repos"

# --- Rama por entorno ---
# La versión de Odoo es un parámetro, no una constante: sale de .env y acompaña
# al tag de la imagen. Staging deriva de producción, nunca se declara aparte.

if [ -f .env ]; then . ./.env; fi
RAMA_PROD="${ODOO_BRANCH:-19.0}"
RAMA_STAG="${RAMA_PROD}-stag"

FAILED=0

fail() { echo "addons.sh: $1" >&2; FAILED=1; }
warn() { echo "addons.sh: aviso: $1" >&2; }

# --- Manifiesto ---
# require_manifest corre en el shell principal — un exit dentro de manifest_entries
# (consumida vía <(...)) solo mataría la subshell, en silencio, sin abortar el script.

require_manifest() {
  [ -f "$MANIFEST" ] || { echo "addons.sh: no existe $MANIFEST" >&2; exit 1; }
}

manifest_entries() {
  grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" || true
}

module_name() { basename "$1" .git; }

valid_category() {
  case "$1" in
    custom-addons|oca|third-party|enterprise) return 0 ;;
    *) return 1 ;;
  esac
}

ROOT="$(pwd)"

# --- Clon bare por módulo ---
# clone --bare no configura refspec de ramas remotas; sin esto origin/<rama> no existe.

ensure_bare() {
  local url="$1" bare="$2" err
  if [ ! -d "$bare" ]; then
    if ! err=$(git clone --bare -- "$url" "$bare" 2>&1); then
      fail "$(module_name "$url"): clonado bare falló — $err"
      return 1
    fi
    git -C "$bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  fi
  if ! err=$(git -C "$bare" fetch --prune origin 2>&1); then
    fail "$(module_name "$url"): fetch de origin falló — $err"
    return 1
  fi
  if git -C "$bare" remote get-url upstream >/dev/null 2>&1; then
    git -C "$bare" fetch --prune upstream >/dev/null 2>&1 || warn "$(module_name "$url"): fetch de upstream falló"
  fi
  return 0
}

# --- Worktrees ---
# Paths absolutos: relativos se resuelven contra el cwd del bare, no el repo.

ensure_worktrees() {
  local bare="$1" prod="$2" stag="$3" name="$4" err

  git -C "$bare" worktree prune

  if [ ! -d "$prod" ]; then
    if ! err=$(git -C "$bare" worktree add "$prod" "$RAMA_PROD" 2>&1); then
      fail "$name: worktree de producción falló — $err"
      return 1
    fi
  fi

  if [ ! -d "$stag" ]; then
    if git -C "$bare" show-ref --verify -q "refs/remotes/origin/$RAMA_STAG"; then
      if ! err=$(git -C "$bare" worktree add "$stag" "$RAMA_STAG" 2>&1); then
        fail "$name: worktree de staging falló — $err"
        return 1
      fi
    else
      if ! err=$(git -C "$bare" worktree add -b "$RAMA_STAG" "$stag" "origin/$RAMA_PROD" 2>&1); then
        fail "$name: bootstrap de $RAMA_STAG falló — $err"
        return 1
      fi
    fi
  fi
  return 0
}

# --- Actualización ---
# Producción avanza siempre (ff-only). Staging se reescribe: es descartable en
# todo momento, así que un reset --hard nunca pierde nada que no exista en GitHub.

update_worktrees() {
  local bare="$1" prod="$2" stag="$3" name="$4" err

  if [ -n "$(git -C "$prod" status --porcelain)" ]; then
    fail "$name: producción tiene cambios sin commitear, no se actualiza"
  elif ! err=$(git -C "$prod" merge --ff-only "origin/$RAMA_PROD" 2>&1); then
    fail "$name: merge --ff-only en producción falló — $err"
  fi

  if git -C "$bare" show-ref --verify -q "refs/remotes/origin/$RAMA_STAG"; then
    if ! err=$(git -C "$stag" reset --hard "origin/$RAMA_STAG" 2>&1); then
      fail "$name: reset --hard en staging falló — $err"
    fi
  else
    warn "$name: $RAMA_STAG no existe en el remoto todavía, staging sigue en su rama local"
  fi
  return 0
}

sync_repo() {
  local url="$1" category="$2" name bare prod stag
  name=$(module_name "$url")
  bare="$BARE_DIR/$name.git"
  prod="$ROOT/addons/production/$category/$name"
  stag="$ROOT/addons/staging/$category/$name"

  ensure_bare "$url" "$bare" || return
  ensure_worktrees "$bare" "$prod" "$stag" "$name" || return
  update_worktrees "$bare" "$prod" "$stag" "$name"
}

cmd_sync() {
  local url category invalid=0
  require_manifest

  # --- Validación previa: categoría inválida aborta antes de clonar nada ---

  while read -r url category; do
    if ! valid_category "$category"; then
      echo "addons.sh: categoría inválida '$category' para $url en $MANIFEST" >&2
      invalid=1
    fi
  done < <(manifest_entries)
  if [ "$invalid" -ne 0 ]; then
    echo "addons.sh: manifiesto inválido, no se clona nada" >&2
    exit 1
  fi

  # --- Sync por repo: cada llamada guardada con || true, sync_repo ya acumula en FAILED ---

  while read -r url category; do
    sync_repo "$url" "$category" || true
  done < <(manifest_entries)

  if [ "$FAILED" -ne 0 ]; then
    echo "addons.sh: sync terminó con errores — ver arriba" >&2
    exit 1
  fi
}

# --- Estado de un worktree ---
# Puro host: rama, commit corto, y si hay cambios sin commitear.

print_row() {
  local env="$1" category="$2" name="$3" tree="$4" branch commit dirty
  if [ ! -d "$tree" ]; then
    printf '%-10s %-14s %-24s %s\n' "$env" "$category" "$name" "(sin worktree)"
    return
  fi
  branch=$(git -C "$tree" rev-parse --abbrev-ref HEAD)
  commit=$(git -C "$tree" rev-parse --short HEAD)
  if [ -n "$(git -C "$tree" status --porcelain)" ]; then dirty="sucio"; else dirty="limpio"; fi
  printf '%-10s %-14s %-24s %-20s %-9s %s\n' "$env" "$category" "$name" "$branch" "$commit" "$dirty"
}

# --- Huérfanos ---
# Presentes en disco, ausentes del manifiesto; no se tocan, solo se listan.

list_orphans() {
  local known=" " url env cat_dir repo_dir n
  while read -r url _; do
    known="$known $(module_name "$url") "
  done < <(manifest_entries)

  for env in production staging; do
    for cat_dir in "addons/$env"/*/; do
      [ -d "$cat_dir" ] || continue
      for repo_dir in "$cat_dir"*/; do
        [ -d "$repo_dir" ] || continue
        n=$(basename "$repo_dir")
        case "$known" in *" $n "*) continue ;; esac
        echo "huérfano: $env/$(basename "$cat_dir")/$n (no está en $MANIFEST)"
      done
    done
  done
}

cmd_status() {
  local url category name env
  require_manifest

  while read -r url category; do
    name=$(module_name "$url")
    for env in production staging; do
      print_row "$env" "$category" "$name" "addons/$env/$category/$name"
    done
  done < <(manifest_entries)

  list_orphans
}

case "${1:-}" in
  sync) shift; cmd_sync "$@" ;;
  status) shift; cmd_status "$@" ;;
  *) echo "uso: $(basename "$0") sync|status" >&2; exit 2 ;;
esac
