#!/usr/bin/env bash
# Contrato de dependencias de addons
# Verifica descubrimiento, cobertura, overrides y fijación de referencias Git.

cd "$(dirname "$0")/.."
. tests/lib.sh

REPO_ROOT="$PWD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Checkout mínimo
# Cada caso recibe el script real y un runtime aislado de staging.
crear_checkout() {
  local root="$TMP/$1"
  mkdir -p "$root/scripts/lib" "$root/runtime/addons/custom/staging" "$root/runtime/staging"
  cp "$REPO_ROOT/scripts/pydeps.sh" "$root/scripts/"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$REPO_ROOT/scripts/lib/contexto.sh" "$root/scripts/lib/"
  printf 'name: prueba-staging\nservices: {}\n' > "$root/runtime/staging/compose.yaml"
  printf 'COMPOSE_PROJECT_NAME=prueba-staging\nODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\nADDONS_REF=19.0-stag\n' \
    > "$root/runtime/staging/compose.env"
  : > "$root/runtime/addons/requirements.override.txt"
  printf '%s' "$root"
}

# Fixtures de addons
# Los requisitos pueden vivir en la raíz del repositorio o junto a un módulo.
declarar_modulo() {
  local root="$1" repo="$2" modulo="$3"; shift 3
  local dir="$root/runtime/addons/custom/staging/$repo/$modulo" deps
  mkdir -p "$dir"
  if [ "$#" -eq 0 ]; then
    printf "{'name': '%s'}\n" "$modulo" > "$dir/__manifest__.py"
  else
    deps=$(printf "'%s', " "$@")
    printf "{'name': '%s', 'external_dependencies': {'python': [%s]}}\n" "$modulo" "$deps" \
      > "$dir/__manifest__.py"
  fi
}

requisitos_repo() {
  local root="$1" repo="$2"; shift 2
  mkdir -p "$root/runtime/addons/custom/staging/$repo"
  printf '%s\n' "$@" > "$root/runtime/addons/custom/staging/$repo/requirements.txt"
}

requisitos_modulo() {
  local root="$1" repo="$2" modulo="$3"; shift 3
  printf '%s\n' "$@" > "$root/runtime/addons/custom/staging/$repo/$modulo/requirements.txt"
}

check() { (cd "$1" && ENTORNO=staging ./scripts/pydeps.sh check 2>&1); }
check_code() { (cd "$1" && ENTORNO=staging ./scripts/pydeps.sh check >/dev/null 2>&1; echo $?); }
compile() { (cd "$1" && ENTORNO=staging ./scripts/pydeps.sh compile 2>&1); }
compile_code() { (cd "$1" && ENTORNO=staging ./scripts/pydeps.sh compile >/dev/null 2>&1; echo $?); }

# Repositorio Git local
# Permite probar refs móviles y SHAs sin depender de red.
crear_remoto() {
  local name="$1" root
  root="$TMP/remotos/$name"
  mkdir -p "$root"
  git -c init.defaultBranch=main init -q "$root"
  git -C "$root" config user.email test@example.invalid
  git -C "$root" config user.name test
  printf 'fixture\n' > "$root/contenido.txt"
  git -C "$root" add contenido.txt
  git -C "$root" commit -qm inicial
  printf '%s' "$root"
}

# =====================================================================
titulo "sin dependencias: valida y compila un lock vacío"
# =====================================================================

ROOT=$(crear_checkout vacio)
declarar_modulo "$ROOT" repo modulo
igual "check termina bien" "0" "$(check_code "$ROOT")"
igual "compile termina bien" "0" "$(compile_code "$ROOT")"
igual "el lock queda vacío" "0" "$([ ! -s "$ROOT/runtime/addons/requirements.lock.txt" ]; echo $?)"

# =====================================================================
titulo "descubrimiento: conserva rangos desde raíz y módulo"
# =====================================================================

ROOT=$(crear_checkout descubrimiento)
declarar_modulo "$ROOT" repo servidor 'authlib>=1.6.12,<1.7.0' packaging
requisitos_repo "$ROOT" repo 'authlib>=1.6.12,<1.7.0'
requisitos_modulo "$ROOT" repo servidor packaging
igual "los dos requirements cubren el manifiesto" "0" "$(check_code "$ROOT")"
igual "compile termina bien" "0" "$(compile_code "$ROOT")"
LOCK=$(cat "$ROOT/runtime/addons/requirements.lock.txt")
contiene "conserva el rango de authlib" 'authlib>=1.6.12,<1.7.0' "$LOCK"
contiene "conserva el requisito del módulo" 'packaging' "$LOCK"
contiene "registra la procedencia" '# Fuente: custom/staging/repo/requirements.txt' "$LOCK"

# =====================================================================
titulo "override: cubre aliases que el repositorio no declara"
# =====================================================================

ROOT=$(crear_checkout override)
declarar_modulo "$ROOT" repo afip OpenSSL
printf 'pyOpenSSL==25.3.0\n' > "$ROOT/runtime/addons/requirements.override.txt"
igual "pyOpenSSL cubre el import OpenSSL" "0" "$(check_code "$ROOT")"
compile "$ROOT" >/dev/null
contiene "el override llega al lock" 'pyOpenSSL==25.3.0' \
  "$(cat "$ROOT/runtime/addons/requirements.lock.txt")"

ROOT=$(crear_checkout reemplazo_override)
declarar_modulo "$ROOT" repo afip pysimplesoap
requisitos_repo "$ROOT" repo 'git+https://example.invalid/pysimplesoap.git@0123456789012345678901234567890123456789'
printf 'pysimplesoap==1.8.22\n' > "$ROOT/runtime/addons/requirements.override.txt"
igual "el override puede reemplazar una fuente del repositorio" "0" "$(compile_code "$ROOT")"
LOCK=$(cat "$ROOT/runtime/addons/requirements.lock.txt")
contiene "conserva el reemplazo local" 'pysimplesoap==1.8.22' "$LOCK"
no_contiene "descarta la fuente reemplazada" 'example.invalid' "$LOCK"

# =====================================================================
titulo "VCS: fija HEAD y ramas a commits completos"
# =====================================================================

ROOT=$(crear_checkout vcs)
PYAFIP=$(crear_remoto pyafipws)
SIMPLE=$(crear_remoto pysimplesoap)
git -C "$SIMPLE" branch stable_py3k
PYAFIP_SHA=$(git -C "$PYAFIP" rev-parse HEAD)
SIMPLE_SHA=$(git -C "$SIMPLE" rev-parse HEAD)
declarar_modulo "$ROOT" localizacion afip pyafipws pysimplesoap
requisitos_repo "$ROOT" localizacion \
  "git+file://$PYAFIP" \
  "git+file://$SIMPLE@stable_py3k" \
  "git+file://$PYAFIP@$PYAFIP_SHA#egg=otro_paquete"
igual "check reconoce nombres desde las URL" "0" "$(check_code "$ROOT")"
igual "compile resuelve las refs locales" "0" "$(compile_code "$ROOT")"
LOCK=$(cat "$ROOT/runtime/addons/requirements.lock.txt")
contiene "HEAD queda fijado" "# VCS: file://$PYAFIP@$PYAFIP_SHA" "$LOCK"
contiene "la rama queda fijada" "# VCS: file://$SIMPLE@$SIMPLE_SHA" "$LOCK"
contiene "un SHA completo se conserva" "# VCS: file://$PYAFIP@$PYAFIP_SHA#egg=otro_paquete" "$LOCK"
contiene "pip recibe fuentes locales" 'file:///tmp/requirements.sources/' "$LOCK"
igual "genera un archivo por repositorio" "2" \
  "$(find "$ROOT/runtime/addons/requirements.sources" -type f | wc -l | tr -d ' ')"
no_contiene "el lock no conserva la rama móvil" '@stable_py3k' "$LOCK"

# =====================================================================
titulo "cobertura: una dependencia sin requirements falla"
# =====================================================================

ROOT=$(crear_checkout faltante)
declarar_modulo "$ROOT" repo modulo phonenumbers
igual "check falla" "1" "$(check_code "$ROOT")"
contiene "nombra la dependencia faltante" 'phonenumbers' "$(check "$ROOT")"
printf 'phonenumbers==9.0.0\n' > "$ROOT/runtime/addons/requirements.txt"
igual "el archivo legacy no cubre el manifiesto" "1" "$(check_code "$ROOT")"

# =====================================================================
titulo "conflictos: dos pines exactos distintos fallan"
# =====================================================================

ROOT=$(crear_checkout conflicto)
declarar_modulo "$ROOT" repo_a modulo_a bokeh
declarar_modulo "$ROOT" repo_b modulo_b bokeh
requisitos_repo "$ROOT" repo_a 'bokeh==3.9.0'
requisitos_repo "$ROOT" repo_b 'bokeh==3.10.0'
igual "check rechaza el conflicto" "1" "$(check_code "$ROOT")"
contiene "explica los pines incompatibles" 'pines incompatibles' "$(check "$ROOT")"

ROOT=$(crear_checkout conflicto_fuente)
declarar_modulo "$ROOT" repo modulo pyafipws
requisitos_repo "$ROOT" repo 'git+https://example.invalid/pyafipws.git@0123456789012345678901234567890123456789'
requisitos_modulo "$ROOT" repo modulo pyafipws
igual "check rechaza índice junto a fuente directa" "1" "$(check_code "$ROOT")"
contiene "explica la mezcla de fuentes" 'mezcla una fuente directa' "$(check "$ROOT")"

# =====================================================================
titulo "formatos: las directivas no aplanables fallan explícitamente"
# =====================================================================

ROOT=$(crear_checkout directiva)
declarar_modulo "$ROOT" repo modulo requests
requisitos_repo "$ROOT" repo '-r requirements-base.txt'
igual "check rechaza includes relativos" "1" "$(check_code "$ROOT")"
contiene "explica la directiva no soportada" 'directiva no soportada' "$(check "$ROOT")"

# =====================================================================
titulo "contrato: exige entorno y manifiestos literales válidos"
# =====================================================================

ROOT=$(crear_checkout invalido)
mkdir -p "$ROOT/runtime/addons/custom/staging/repo/modulo"
printf "{'name': 'incompleto'" > "$ROOT/runtime/addons/custom/staging/repo/modulo/__manifest__.py"
igual "un manifiesto inválido detiene check" "1" "$(check_code "$ROOT")"
contiene "explica el manifiesto inválido" 'manifiestos inválidos' "$(check "$ROOT")"
igual "sin ENTORNO falla antes de leer addons" "2" \
  "$(cd "$ROOT" && env -u ENTORNO ./scripts/pydeps.sh check >/dev/null 2>&1; echo $?)"

resumen
