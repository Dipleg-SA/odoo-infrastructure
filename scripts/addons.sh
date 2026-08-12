#!/usr/bin/env bash
# Addons por bind-mount. sync reconstruye/actualiza el árbol, status
# imprime el estado de cada worktree. Sin dependencias fuera de git.
set -euo pipefail
shopt -s nullglob

cd "$(dirname "$0")/.."

# --- Entorno ---
# El source va primero: si viniera después, una variable homónima en .env pisaría
# las constantes de abajo y el script buscaría el manifiesto en otro lado.

if [ -f .env ]; then . ./.env; fi

MANIFEST="config/odoo/addons.txt"
BARE_DIR="addons/.repos"

# --- Rama de los addons ---
# Un árbol por checkout: qué entorno es este lo dice .env, no un subdirectorio.
# El default sale del tag de la imagen, único lugar donde vive la versión de Odoo.

ADDONS_BRANCH="${ADDONS_BRANCH:-$(sed -n 's/^FROM odoo:\([0-9.]*\).*/\1/p' docker/odoo/Dockerfile | head -1)}"

if [ -z "$ADDONS_BRANCH" ]; then
  echo "addons.sh: no se pudo leer la versión del tag FROM odoo: del Dockerfile" >&2
  echo "addons.sh: declarar ADDONS_BRANCH en .env" >&2
  exit 1
fi

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

# --- Worktree ---
# Uno solo, en la rama que declara el checkout. Path absoluto: uno relativo se
# resolvería contra el cwd del bare, no contra el repo.

ensure_worktree() {
  local bare="$1" tree="$2" name="$3" err
  git -C "$bare" worktree prune
  [ -d "$tree" ] && return 0
  if ! err=$(git -C "$bare" worktree add "$tree" "$ADDONS_BRANCH" 2>&1); then
    fail "$name: worktree en $ADDONS_BRANCH falló — $err"
    return 1
  fi
  return 0
}

# --- Actualización ---
# Solo avanza si el worktree está en la rama declarada: en un checkout de
# desarrollo HEAD vive en una feat/*, y ahí sync no tiene nada que hacer.
#
# ff-only y nunca reset: el script no sabe si la rama de este checkout es
# descartable. Una rama de staging se reescribe a propósito y su reset es
# inofensivo; la de producción no, y ahí un reset se comería un commit local.
# Ante una divergencia nombra el comando y deja la decisión al operador.

update_worktree() {
  local tree="$1" name="$2" err actual
  actual=$(git -C "$tree" rev-parse --abbrev-ref HEAD)

  if [ "$actual" != "$ADDONS_BRANCH" ]; then
    warn "$name: el worktree está en '$actual', no en '$ADDONS_BRANCH' — no se actualiza"
    return 0
  fi
  if [ -n "$(git -C "$tree" status --porcelain)" ]; then
    fail "$name: hay cambios sin commitear, no se actualiza"
    return 0
  fi
  if ! git -C "$tree" show-ref --verify -q "refs/remotes/origin/$ADDONS_BRANCH"; then
    warn "$name: origin/$ADDONS_BRANCH no existe en el remoto todavía, el worktree sigue en su rama local"
    return 0
  fi
  if ! err=$(git -C "$tree" merge --ff-only "origin/$ADDONS_BRANCH" 2>&1); then
    if git -C "$tree" merge-base --is-ancestor "origin/$ADDONS_BRANCH" HEAD 2>/dev/null; then
      fail "$name: el worktree tiene commits que no están en origin/$ADDONS_BRANCH — este checkout no debería escribir"
    else
      fail "$name: origin/$ADDONS_BRANCH fue reescrita, el merge no avanza en línea recta.
            Si esa rama es descartable (staging), rehacela con:
              git -C addons/$(basename "$(dirname "$tree")")/$name reset --hard origin/$ADDONS_BRANCH
            Detalle: $err"
    fi
  fi
  return 0
}

sync_repo() {
  local url="$1" category="$2" name bare tree
  name=$(module_name "$url")
  bare="$BARE_DIR/$name.git"
  tree="$ROOT/addons/$category/$name"

  ensure_bare "$url" "$bare" || return
  ensure_worktree "$bare" "$tree" "$name" || return
  update_worktree "$tree" "$name"
}

cmd_sync() {
  local url category invalid=0 viejo
  require_manifest

  # --- Manifiesto sin entradas ---
  # Es el estado por defecto de un repo recién clonado. Sin al menos un repo no
  # hay addons_path y el entrypoint de Odoo aborta una fase despues, asi que
  # terminar en silencio con exit 0 seria mentir sobre lo que paso.

  if [ -z "$(manifest_entries)" ]; then
    echo "addons.sh: $MANIFEST no declara ningún repositorio — el árbol queda vacío" >&2
    echo "addons.sh: agregá al menos una línea 'URL categoría' antes de levantar Odoo" >&2
    exit 1
  fi

  # --- Árbol viejo por entorno ---
  # Sus worktrees siguen registrados en el bare y retienen la rama, así que el
  # add en la ruta nueva fallaría con "already checked out". Lo borra el operador.

  for viejo in addons/production addons/staging addons/development; do
    if [ -d "$viejo" ]; then
      echo "addons.sh: existe $viejo, del layout por entorno anterior — retiene la rama y bloquea el árbol nuevo" >&2
      echo "addons.sh: borralo (rm -rf addons/production addons/staging addons/development) y volvé a correr el sync" >&2
      exit 1
    fi
  done

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
  local category="$1" name="$2" tree="$3" branch commit dirty
  if [ ! -d "$tree" ]; then
    printf '%-14s %-24s %s\n' "$category" "$name" "(sin worktree)"
    return
  fi
  branch=$(git -C "$tree" rev-parse --abbrev-ref HEAD)
  commit=$(git -C "$tree" rev-parse --short HEAD)
  if [ -n "$(git -C "$tree" status --porcelain)" ]; then dirty="sucio"; else dirty="limpio"; fi
  printf '%-14s %-24s %-20s %-9s %s\n' "$category" "$name" "$branch" "$commit" "$dirty"
}

# --- Huérfanos ---
# Presentes en disco, ausentes del manifiesto; no se tocan, solo se listan.
# El glob no alcanza a .repos/: los directorios ocultos no matchean sin dotglob.

list_orphans() {
  local known=" " url cat_dir repo_dir n
  while read -r url _; do
    known="$known $(module_name "$url") "
  done < <(manifest_entries)

  for cat_dir in addons/*/; do
    [ -d "$cat_dir" ] || continue
    for repo_dir in "$cat_dir"*/; do
      [ -d "$repo_dir" ] || continue
      n=$(basename "$repo_dir")
      case "$known" in *" $n "*) continue ;; esac
      echo "huérfano: $(basename "$cat_dir")/$n (no está en $MANIFEST)"
    done
  done
}

cmd_status() {
  local url category name
  require_manifest

  echo "rama declarada: $ADDONS_BRANCH"
  echo

  while read -r url category; do
    name=$(module_name "$url")
    print_row "$category" "$name" "addons/$category/$name"
  done < <(manifest_entries)

  list_orphans
}

case "${1:-}" in
  sync) shift; cmd_sync "$@" ;;
  status) shift; cmd_status "$@" ;;
  *) echo "uso: $(basename "$0") sync|status" >&2; exit 2 ;;
esac
