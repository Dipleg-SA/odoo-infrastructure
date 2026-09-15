#!/usr/bin/env bash
# Sincronización de candidatos
# Usa remotos Git locales para verificar catálogo, ramas y aislamiento sin Docker.

cd "$(dirname "$0")/.."
. tests/lib.sh

REPO_ROOT="$PWD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

# Repositorio de prueba
# Cada entorno tiene una revisión distinta para distinguir los candidatos publicados.
crear_addon() {
  local dir="$TMP/remotos/$1" nombre="$1"
  mkdir -p "$dir" && git -C "$dir" init -q -b 19.0
  mkdir -p "$dir/$nombre"
  printf "{'name': '%s'}\n" "$nombre" > "$dir/$nombre/__manifest__.py"
  git -C "$dir" add -A && git -C "$dir" commit -qm "base"
  git -C "$dir" checkout -qb 19.0-dev
  printf 'dev\n' >> "$dir/$nombre/__manifest__.py"
  git -C "$dir" commit -qam "dev"
  git -C "$dir" checkout -q 19.0
  git -C "$dir" checkout -qb 19.0-stag
  printf 'staging\n' >> "$dir/$nombre/__manifest__.py"
  git -C "$dir" commit -qam "staging"
  git -C "$dir" checkout -q 19.0
  printf '%s' "$dir"
}

# Checkout de infraestructura
# El catálogo y los bare clones son compartidos; las composiciones son por runtime.
crear_checkout() {
  local root="$TMP/$1" entorno
  mkdir -p "$root/scripts/lib" "$root/stacks/odoo/image" "$root/runtime/addons"
  cp "$REPO_ROOT/scripts/addons.sh" "$root/scripts/"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$REPO_ROOT/scripts/lib/contexto.sh" \
    "$REPO_ROOT/scripts/lib/candidate-lock.sh" "$root/scripts/lib/"
  cp "$REPO_ROOT/runtime/addons/catalogo.txt.example" "$root/runtime/addons/"
  : > "$root/runtime/addons/catalogo.txt"
  printf 'FROM odoo:19.0\n' > "$root/stacks/odoo/image/Dockerfile"
  for entorno in desarrollo staging produccion; do
    mkdir -p "$root/runtime/$entorno"
    printf 'services: {}\n' > "$root/runtime/$entorno/compose.yaml"
    printf 'COMPOSE_PROJECT_NAME=test-%s\n' "$entorno" > "$root/runtime/$entorno/compose.env"
  done
  printf '%s' "$root"
}

declarar() { printf '%s\n' "$2" >> "$1/runtime/addons/catalogo.txt"; }
ejecutar() {
  local root="$1" entorno="$2" verbo="$3"
  (cd "$root" && ENTORNO="$entorno" ./scripts/addons.sh "$verbo" 2>&1)
}
codigo() {
  local salida retorno
  salida=$(ejecutar "$1" "$2" "$3" 2>&1)
  retorno=$?
  [ "$retorno" -eq 0 ] || printf '%s\n' "$salida" >&2
  printf '%s' "$retorno"
}
commit_candidato() { cat "$1/runtime/addons/custom/$2/$3/.candidate-commit" 2>/dev/null; }

# Ramas por runtime
# Desarrollo, staging y producción publican la revisión de su rama fija.
ADDON=$(crear_addon dominio_ventas)
ROOT=$(crear_checkout caso-ramas)
declarar "$ROOT" "$ADDON"

igual "sin ENTORNO falla antes de clonar" "2" "$(cd "$ROOT" && env -u ENTORNO ./scripts/addons.sh sync >/dev/null 2>&1; echo $?)"
igual "sync de staging termina bien" "0" "$(codigo "$ROOT" staging sync)"
STAGING_COMMIT=$(git -C "$ADDON" rev-parse 19.0-stag)
igual "staging publica el commit de 19.0-stag" "$STAGING_COMMIT" \
  "$(commit_candidato "$ROOT" staging dominio_ventas)"
contiene "staging exporta el código del candidato" "staging" \
  "$(cat "$ROOT/runtime/addons/custom/staging/dominio_ventas/dominio_ventas/__manifest__.py")"
igual "el candidato no es un worktree Git" "0" \
  "$([ ! -e "$ROOT/runtime/addons/custom/staging/dominio_ventas/.git" ]; echo $?)"
igual "el bare compartido vive en runtime/addons" "0" \
  "$([ -d "$ROOT/runtime/addons/.repos/dominio_ventas.git" ]; echo $?)"
contiene "status registra el commit publicado" "$STAGING_COMMIT" \
  "$(ejecutar "$ROOT" staging status)"

igual "sync de desarrollo termina bien" "0" "$(codigo "$ROOT" desarrollo sync)"
DEV_COMMIT=$(git -C "$ADDON" rev-parse 19.0-dev)
igual "desarrollo publica el commit de 19.0-dev" "$DEV_COMMIT" \
  "$(commit_candidato "$ROOT" desarrollo dominio_ventas)"
igual "desarrollo no comparte la ruta de staging" "1" \
  "$([ "$ROOT/runtime/addons/custom/desarrollo/dominio_ventas" -ef "$ROOT/runtime/addons/custom/staging/dominio_ventas" ]; echo $?)"
igual "sync de producción termina bien" "0" "$(codigo "$ROOT" produccion sync)"
PROD_COMMIT=$(git -C "$ADDON" rev-parse 19.0)
igual "producción publica el commit base" "$PROD_COMMIT" \
  "$(commit_candidato "$ROOT" produccion dominio_ventas)"
igual "sync conserva la referencia base de Odoo" "FROM odoo:19.0" \
  "$(cat "$ROOT/stacks/odoo/image/Dockerfile")"
no_contiene "no materializa candidatos en addons raíz" "addons/custom-addons" \
  "$(find "$ROOT" -maxdepth 2 -type d -print)"

# Actualización aislada
# Un fetch nuevo reemplaza solo el candidato de su entorno y conserva los demás.
git -C "$ADDON" checkout -q 19.0-stag
printf 'v2\n' >> "$ADDON/dominio_ventas/__manifest__.py"
git -C "$ADDON" commit -qam "staging v2"
git -C "$ADDON" checkout -q 19.0
PREVIO_DEV=$(commit_candidato "$ROOT" desarrollo dominio_ventas)
PREVIO_PROD=$(commit_candidato "$ROOT" produccion dominio_ventas)
igual "sync actualizado de staging termina bien" "0" "$(codigo "$ROOT" staging sync)"
NUEVO_STAGING=$(git -C "$ADDON" rev-parse 19.0-stag)
igual "staging avanza al nuevo commit" "$NUEVO_STAGING" \
  "$(commit_candidato "$ROOT" staging dominio_ventas)"
igual "desarrollo conserva su commit" "$PREVIO_DEV" \
  "$(commit_candidato "$ROOT" desarrollo dominio_ventas)"
igual "producción conserva su commit" "$PREVIO_PROD" \
  "$(commit_candidato "$ROOT" produccion dominio_ventas)"

# Reemplazo íntegro del candidato
# El código local no se mezcla con la revisión publicada y desaparece al sincronizar.
printf 'edición local\n' >> "$ROOT/runtime/addons/custom/staging/dominio_ventas/dominio_ventas/__manifest__.py"
touch "$ROOT/runtime/addons/custom/staging/dominio_ventas/sobrante.py"
igual "sync reemplaza el candidato completo" "0" "$(codigo "$ROOT" staging sync)"
no_contiene "descarta cambios locales" "edición local" \
  "$(cat "$ROOT/runtime/addons/custom/staging/dominio_ventas/dominio_ventas/__manifest__.py")"
igual "borra archivos que no pertenecen al commit" "1" \
  "$([ -e "$ROOT/runtime/addons/custom/staging/dominio_ventas/sobrante.py" ]; echo $?)"

# Catálogo y fallos de rama
# La validación ocurre antes de clonar, y un fallo remoto conserva el candidato anterior.
ROOT_INVALIDO=$(crear_checkout caso-invalido)
printf '%s custom-addons\n' "$ADDON" > "$ROOT_INVALIDO/runtime/addons/catalogo.txt"
igual "una línea con categoría se rechaza" "1" "$(codigo "$ROOT_INVALIDO" staging sync)"
igual "el catálogo inválido no clona repositorios" "1" \
  "$([ -d "$ROOT_INVALIDO/runtime/addons/.repos" ]; echo $?)"

ROOT_URL_INVALIDA=$(crear_checkout caso-url-invalida)
printf '%s\n' 'https://token@github.com/organizacion/dominio_privado.git' \
  > "$ROOT_URL_INVALIDA/runtime/addons/catalogo.txt"
igual "una URL con credenciales se rechaza" "1" "$(codigo "$ROOT_URL_INVALIDA" produccion sync)"
igual "la URL con credenciales no clona repositorios" "1" \
  "$([ -d "$ROOT_URL_INVALIDA/runtime/addons/.repos" ]; echo $?)"

rm -f "$ROOT/runtime/addons/catalogo.txt"
igual "sin catálogo real falla y no usa la plantilla" "1" "$(codigo "$ROOT" staging sync)"
contiene "y nombra la plantilla para copiar" "runtime/addons/catalogo.txt.example" \
  "$(ejecutar "$ROOT" staging sync)"
printf '%s\n' "$ADDON" > "$ROOT/runtime/addons/catalogo.txt"

RAMA_ANTERIOR=$(commit_candidato "$ROOT" desarrollo dominio_ventas)
git -C "$ADDON" branch -D 19.0-dev >/dev/null
igual "una rama ausente hace fallar el sync" "1" "$(codigo "$ROOT" desarrollo sync)"
igual "un fallo conserva el candidato anterior" "$RAMA_ANTERIOR" \
  "$(commit_candidato "$ROOT" desarrollo dominio_ventas)"

# Catálogo vacío y huérfanos
# Un dominio retirado queda visible para limpieza manual, pero no se borra solo.
: > "$ROOT/runtime/addons/catalogo.txt"
igual "un catálogo vacío es válido" "0" "$(codigo "$ROOT" staging sync)"
contiene "status señala el candidato huérfano" "huérfano: custom/staging/dominio_ventas" \
  "$(ejecutar "$ROOT" staging status)"
igual "el candidato huérfano se conserva" "0" \
  "$([ -d "$ROOT/runtime/addons/custom/staging/dominio_ventas" ]; echo $?)"

resumen
