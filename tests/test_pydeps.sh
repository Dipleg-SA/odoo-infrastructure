#!/usr/bin/env bash
# check contra manifiestos reales, sin red ni Docker. sync solo stubea la
# resolución vía Docker — es la única parte que sale de este proceso.

cd "$(dirname "$0")/.."
. tests/lib.sh

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Checkout mínimo ---
# Solo lo que pydeps.sh toca: requirements.txt y el FROM del Dockerfile para sync.

crear_checkout() {
  local root="$TMP/$1"
  mkdir -p "$root/scripts/lib" "$root/docker/odoo" "$root/addons"
  cp "$REPO_ROOT/scripts/pydeps.sh" "$root/scripts/"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$root/scripts/lib/"
  echo "FROM odoo:19.0-20260810" > "$root/docker/odoo/Dockerfile"
  : > "$root/docker/odoo/requirements.txt"
  printf '%s' "$root"
}

# --- Manifiesto de un módulo, con o sin external_dependencies ---

declarar_modulo() {
  local root="$1" categoria="$2" modulo="$3"; shift 3
  local dir="$root/addons/$categoria/${modulo}_repo/$modulo" deps
  mkdir -p "$dir"
  if [ "$#" -eq 0 ]; then
    printf "{'name': '%s'}\n" "$modulo" > "$dir/__manifest__.py"
  else
    deps=$(printf "'%s', " "$@")
    printf "{'name': '%s', 'external_dependencies': {'python': [%s]}}\n" "$modulo" "$deps" \
      > "$dir/__manifest__.py"
  fi
}

pinear() { printf '%s\n' "$2" >> "$1/docker/odoo/requirements.txt"; }

check()      { (cd "$1" && ./scripts/pydeps.sh check 2>&1); }
check_code() { (cd "$1" && ./scripts/pydeps.sh check >/dev/null 2>&1; echo $?); }
sync_()      { (cd "$1" && PATH="$REPO_ROOT/tests/stubs:$PATH" STUB_DIR="$2" ./scripts/pydeps.sh sync 2>&1); }
sync_code()  { (cd "$1" && PATH="$REPO_ROOT/tests/stubs:$PATH" STUB_DIR="$2" ./scripts/pydeps.sh sync >/dev/null 2>&1; echo $?); }

# =====================================================================
titulo "check: nada declarado, requirements.txt vacío"
# =====================================================================

ROOT=$(crear_checkout caso1)
declarar_modulo "$ROOT" custom-addons mi_modulo

igual "sale con 0" "0" "$(check_code "$ROOT")"
contiene "y lo dice" "cubre lo que declaran" "$(check "$ROOT")"

# =====================================================================
titulo "check: falta un pin"
# =====================================================================

ROOT=$(crear_checkout caso2)
declarar_modulo "$ROOT" custom-addons mi_modulo phonenumbers

igual "sale con 1" "1" "$(check_code "$ROOT")"
contiene "y nombra el paquete que falta" "phonenumbers" "$(check "$ROOT")"

# =====================================================================
titulo "check: cubierto, pasa"
# =====================================================================

pinear "$ROOT" "phonenumbers==8.13.42"
igual "sale con 0" "0" "$(check_code "$ROOT")"

# =====================================================================
titulo "check: normaliza mayúsculas y guion/guion bajo"
# =====================================================================

ROOT=$(crear_checkout caso3)
declarar_modulo "$ROOT" oca otro_modulo Python-Dateutil
pinear "$ROOT" "python_dateutil==2.9.0"

igual "'Python-Dateutil' declarado == 'python_dateutil' pineado" "0" "$(check_code "$ROOT")"

# =====================================================================
titulo "check: huérfano — avisa, no falla"
# =====================================================================

ROOT=$(crear_checkout caso4)
declarar_modulo "$ROOT" custom-addons mi_modulo
pinear "$ROOT" "requests==2.31.0"

igual "sigue en 0" "0" "$(check_code "$ROOT")"
contiene "pero avisa del pin sin dueño" "requests" "$(check "$ROOT")"

# =====================================================================
titulo "sync: nada que resolver, no toca Docker"
# =====================================================================

ROOT=$(crear_checkout caso5)
declarar_modulo "$ROOT" custom-addons mi_modulo
STUB=$(mktemp -d)

igual "sale con 0" "0" "$(sync_code "$ROOT" "$STUB")"
contiene "y lo dice" "nada nuevo que pinear" "$(sync_ "$ROOT" "$STUB")"
igual "no invocó Docker" "1" "$([ -f "$STUB/llamadas" ]; echo $?)"
rm -rf "$STUB"

# =====================================================================
titulo "sync: resuelve lo que falta contra la imagen base"
# =====================================================================

ROOT=$(crear_checkout caso6)
declarar_modulo "$ROOT" custom-addons mi_modulo phonenumbers
STUB=$(mktemp -d)
cat > "$STUB/salida" <<'JSON'
{"version": "1", "install": [{"metadata": {"name": "phonenumbers", "version": "8.13.42"}}]}
JSON

igual "sale con 0" "0" "$(sync_code "$ROOT" "$STUB")"
contiene "invocó la imagen del Dockerfile" "odoo:19.0-20260810" "$(cat "$STUB/llamadas")"
contiene "y le pidió el paquete que faltaba" "phonenumbers" "$(cat "$STUB/llamadas")"
igual "quedó pineado con la versión resuelta" "0" \
  "$(grep -qx 'phonenumbers==8.13.42' "$ROOT/docker/odoo/requirements.txt"; echo $?)"
rm -rf "$STUB"

# =====================================================================
titulo "sync: nunca reescribe un pin ya puesto"
# =====================================================================

ROOT=$(crear_checkout caso7)
declarar_modulo "$ROOT" custom-addons mi_modulo phonenumbers requests
pinear "$ROOT" "requests==2.28.0"
STUB=$(mktemp -d)
cat > "$STUB/salida" <<'JSON'
{"version": "1", "install": [{"metadata": {"name": "phonenumbers", "version": "8.13.42"}}]}
JSON

sync_code "$ROOT" "$STUB" >/dev/null
no_contiene "no le pidió a Docker resolver lo ya pineado" "requests" \
  "$(grep -o 'requests' "$STUB/llamadas" || true)"
igual "el pin viejo de requests sigue intacto" "0" \
  "$(grep -qx 'requests==2.28.0' "$ROOT/docker/odoo/requirements.txt"; echo $?)"
igual "y el nuevo de phonenumbers se agregó" "0" \
  "$(grep -qx 'phonenumbers==8.13.42' "$ROOT/docker/odoo/requirements.txt"; echo $?)"
rm -rf "$STUB"

resumen
