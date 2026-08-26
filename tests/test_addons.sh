#!/usr/bin/env bash
# addons.sh de punta a punta, con repos git de verdad. No necesita Docker ni red:
# el "remoto" es un directorio local, que para git es un remoto como cualquier otro.
#
# Es el script con más lógica del repo y el único que no invoca Docker ni una vez,
# así que es el que más se gana testeando.

cd "$(dirname "$0")/.."
. tests/lib.sh

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Identidad para los commits de los fixtures, sin tocar la config del operador.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

# --- Repo de addon "de terceros" ---
# Con dos ramas, como los del manifiesto: la de la versión y la de staging.

crear_addon() {
  local dir="$TMP/remotos/$1"
  mkdir -p "$dir" && git -C "$dir" init -q -b 19.0
  mkdir -p "$dir/$1"
  echo "{'name': '$1'}" > "$dir/$1/__manifest__.py"
  git -C "$dir" add -A && git -C "$dir" commit -qm "v1"
  git -C "$dir" branch 19.0-stag
  printf '%s' "$dir"
}

# --- Checkout mínimo de infra ---
# Solo lo que addons.sh toca: él hace cd al padre de su propio directorio, así que
# copiarlo dentro del árbol falso alcanza para que se ubique.

crear_checkout() {
  local root="$TMP/$1" rama="$2"
  mkdir -p "$root/scripts/lib" "$root/addons" "$root/docker/app/odoo"
  cp "$REPO_ROOT/scripts/addons.sh" "$root/scripts/"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$root/scripts/lib/"
  echo "FROM odoo:19.0" > "$root/docker/app/odoo/Dockerfile"
  : > "$root/addons/addons.txt"
  [ -n "$rama" ] && echo "ADDONS_BRANCH=$rama" > "$root/.env"
  printf '%s' "$root"
}

declarar() { printf '%s\t%s\n' "$2" "$3" >> "$1/addons/addons.txt"; }
sync()     { (cd "$1" && ./scripts/addons.sh sync 2>&1); }
estado()   { (cd "$1" && ./scripts/addons.sh status 2>&1); }
sync_code(){ (cd "$1" && ./scripts/addons.sh sync >/dev/null 2>&1; echo $?); }

# =====================================================================
titulo "sync inicial"
# =====================================================================

ADDON=$(crear_addon mi_modulo)
ROOT=$(crear_checkout caso1 19.0-stag)
declarar "$ROOT" "$ADDON" custom-addons

igual "sync sale con 0" "0" "$(sync_code "$ROOT")"
igual "deja el worktree en la rama declarada y limpio" "19.0-stag" \
  "$(git -C "$ROOT/addons/custom-addons/mi_modulo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
contiene "status lo reporta limpio" "limpio" "$(estado "$ROOT")"
igual "el módulo quedó en disco" "0" \
  "$([ -f "$ROOT/addons/custom-addons/mi_modulo/mi_modulo/__manifest__.py" ]; echo $?)"

# El clon bare es compartido y los worktrees cuelgan de él.
igual "el clon bare vive bajo .repos" "0" "$([ -d "$ROOT/addons/.repos/mi_modulo.git" ]; echo $?)"

# =====================================================================
titulo "el remoto avanza"
# =====================================================================

echo "v2" >> "$ADDON/mi_modulo/__manifest__.py"
git -C "$ADDON" checkout -q 19.0-stag && git -C "$ADDON" commit -qam "v2"

igual "sync sale con 0" "0" "$(sync_code "$ROOT")"
contiene "el worktree avanzó por fast-forward" "v2" \
  "$(git -C "$ROOT/addons/custom-addons/mi_modulo" log --oneline -1)"

# =====================================================================
titulo "rama de feature: sync no toca nada"
# =====================================================================

git -C "$ROOT/addons/custom-addons/mi_modulo" checkout -q -b feat/mi-cambio
ANTES=$(git -C "$ROOT/addons/custom-addons/mi_modulo" rev-parse HEAD)
SALIDA=$(sync "$ROOT")

igual    "sync sale con 0" "0" "$(sync_code "$ROOT")"
contiene "avisa que no actualiza" "no se actualiza" "$SALIDA"
igual    "y deja el worktree donde estaba" "$ANTES" \
  "$(git -C "$ROOT/addons/custom-addons/mi_modulo" rev-parse HEAD)"

# =====================================================================
titulo "commits locales sin pushear: es el estado normal entre el commit y el push"
# =====================================================================

git -C "$ROOT/addons/custom-addons/mi_modulo" checkout -q 19.0-stag
echo "mi cambio" >> "$ROOT/addons/custom-addons/mi_modulo/mi_modulo/__manifest__.py"
git -C "$ROOT/addons/custom-addons/mi_modulo" commit -qam "feat: mi cambio"

igual    "sync NO lo trata como error" "0" "$(sync_code "$ROOT")"
contiene "y el commit local sigue ahí" "feat: mi cambio" \
  "$(git -C "$ROOT/addons/custom-addons/mi_modulo" log --oneline -1)"
contiene "pero avisa, porque un re-clone se lo comería" "1 commit(s) locales sin pushear" \
  "$(sync "$ROOT")"

# =====================================================================
titulo "divergencia: yo commiteé y el remoto también"
# =====================================================================

echo "ajeno" >> "$ADDON/mi_modulo/otro.py"
git -C "$ADDON" add -A && git -C "$ADDON" commit -qm "feat: cambio ajeno"

MIO=$(git -C "$ROOT/addons/custom-addons/mi_modulo" rev-parse HEAD)
SALIDA=$(sync "$ROOT")

igual    "sync falla, para que el operador decida" "1" "$(sync_code "$ROOT")"
contiene "cuenta los commits de cada lado" "1 commit(s) locales, 1 en el remoto" "$SALIDA"
contiene "propone integrar con rebase"     "rebase origin/19.0-stag"             "$SALIDA"
contiene "y condiciona el reset a que sean descartables" "solo si esos 1 commit(s) locales son descartables" "$SALIDA"
no_contiene "no dice que la rama fue reescrita" "fue reescrita" "$SALIDA"
contiene "y arrastra el error real de git"  "Detalle:" "$SALIDA"

# Lo más importante del caso: que no haya tocado el trabajo local.
igual "el worktree queda intacto" "$MIO" "$(git -C "$ROOT/addons/custom-addons/mi_modulo" rev-parse HEAD)"

# Y que el comando que sugiere funcione tal cual.
git -C "$ROOT/addons/custom-addons/mi_modulo" rebase -q origin/19.0-stag >/dev/null 2>&1
igual "después del rebase que propone, el sync pasa" "0" "$(sync_code "$ROOT")"

# =====================================================================
titulo "manifiesto: se valida antes de clonar nada"
# =====================================================================

ROOT2=$(crear_checkout caso2 19.0-stag)
igual    "un manifiesto vacío aborta" "1" "$(sync_code "$ROOT2")"
contiene "y dice por qué" "no declara ningún repositorio" "$(sync "$ROOT2")"

declarar "$ROOT2" "$ADDON" categoria-inventada
SALIDA=$(sync "$ROOT2")
igual    "una categoría inválida aborta" "1" "$(sync_code "$ROOT2")"
contiene "nombrando la categoría"        "categoria-inventada" "$SALIDA"
igual    "sin haber clonado nada"        "1" "$([ -d "$ROOT2/addons/.repos" ]; echo $?)"

# =====================================================================
titulo "guardas del layout viejo y de los huérfanos"
# =====================================================================

ROOT3=$(crear_checkout caso3 19.0-stag)
declarar "$ROOT3" "$ADDON" custom-addons
mkdir -p "$ROOT3/addons/production"
SALIDA=$(sync "$ROOT3")
igual    "un árbol por entorno del layout anterior aborta" "1" "$(sync_code "$ROOT3")"
contiene "y nombra el rm que lo destraba" "rm -rf addons/production" "$SALIDA"

rm -rf "$ROOT3/addons/production"
sync "$ROOT3" >/dev/null 2>&1
mkdir -p "$ROOT3/addons/oca/repo_ajeno"
contiene "status lista lo que no está en el manifiesto" "huérfano: oca/repo_ajeno" "$(estado "$ROOT3")"

resumen
