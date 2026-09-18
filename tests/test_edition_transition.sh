#!/usr/bin/env bash
# Contrato de compatibilidad Community y Enterprise
# Verifica la base vigente contra la procedencia del build seleccionado, sin slots de imagen.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
ROOT="$TMP/repo"
mkdir -p "$ROOT/scripts/lib" "$ROOT/runtime/produccion" \
  "$ROOT/runtime/addons/builds/produccion/seleccionada" "$TMP/bin"
export STUB_DIR="$TMP"
export PATH="$TMP/bin:$PATH"
trap 'rm -rf "$TMP"' EXIT

cp scripts/lib/contexto.sh scripts/odoo-edition-check.sh scripts/lib/ui.sh \
  "$ROOT/scripts/"
cp scripts/lib/contexto.sh scripts/lib/ui.sh "$ROOT/scripts/lib/"
chmod 755 "$ROOT/scripts/odoo-edition-check.sh"

cat > "$ROOT/runtime/produccion/compose.yaml" <<'EOF'
services: {}
EOF
cat > "$ROOT/runtime/produccion/compose.env" <<'EOF'
COMPOSE_PROJECT_NAME=transition-test
ODOO_EDITION=enterprise
TAG=19.0-ee-2026-09-16
ODOO_IMAGE=local/odoo:19.0-produccion-20260917T183719Z-fa588059f4932d2f
EOF
cat > "$ROOT/runtime/addons/builds/produccion/seleccionada/image.json" <<'EOF'
{"tag":"local/odoo:19.0-produccion-20260917T183719Z-fa588059f4932d2f","edition":"enterprise","enterprise_modules":["ventas"]}
EOF

cat > "$TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/llamadas"
case "$*" in
  *"run --rm --name odoo-edition-check"*)
    printf '%s\n' "ODOO_EDITION_CHECK_MODULES=${EDITION_CHECK_MODULES:-base,ventas}"
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod 755 "$TMP/bin/docker"

titulo "odoo-edition-check.sh — metadata del build seleccionado"
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/odoo-edition-check.sh --destino community 2>&1); codigo=$?
igual "bloquea Community con módulo Enterprise instalado" 1 "$codigo"
contiene "informa el módulo incompatible" "ventas" "$salida"
contiene "consulta la base mediante Odoo ORM" "odoo shell --no-http" "$(cat "$TMP/llamadas")"
no_contiene "no usa image-state" "image-state" "$(cat "$ROOT/scripts/odoo-edition-check.sh")"
no_contiene "no usa images.json" "images.json" "$(cat "$ROOT/scripts/odoo-edition-check.sh")"

export EDITION_CHECK_MODULES=base
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/odoo-edition-check.sh --destino community 2>&1); codigo=$?
igual "permite Community sin módulos Enterprise" 0 "$codigo"
contiene "confirma base compatible" "base compatible con Community" "$salida"

resumen
