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
  "$ROOT/runtime/produccion/addons/enterprise/ventas" \
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
{"tag":"local/odoo:19.0-produccion-20260917T183719Z-fa588059f4932d2f","edition":"enterprise"}
EOF
printf "{'name': 'ventas'}\n" > "$ROOT/runtime/produccion/addons/enterprise/ventas/__manifest__.py"

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
no_contiene "no usa inventario Enterprise de la imagen" "enterprise_modules" "$(cat "$ROOT/scripts/odoo-edition-check.sh")"

export EDITION_CHECK_MODULES=base
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/odoo-edition-check.sh --destino community 2>&1); codigo=$?
igual "permite Community sin módulos Enterprise" 0 "$codigo"
contiene "confirma base compatible" "base compatible con Community" "$salida"

rm "$ROOT/runtime/produccion/addons/enterprise/ventas/__manifest__.py"
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/odoo-edition-check.sh --destino community 2>&1); codigo=$?
igual "bloquea la transición sin checkout Enterprise inventariable" 1 "$codigo"
contiene "explica el checkout faltante" "no se pudo inventariar" "$salida"
printf "{'name': 'ventas'}\n" > "$ROOT/runtime/produccion/addons/enterprise/ventas/__manifest__.py"

# Gate del entrypoint
# Una copia con rutas temporales permite observar addons_path sin tocar el host.
ENTRYPOINT="$ROOT/entrypoint.sh"
ADDONS_FIXTURE="$ROOT/addons"
RUNTIME_CONF_FIXTURE="$ROOT/odoo-runtime.conf"
mkdir -p "$ADDONS_FIXTURE/custom/ventas" "$ADDONS_FIXTURE/enterprise/enterprise_mod" \
  "$ROOT/secrets" "$ROOT/config" "$ROOT/community"
touch "$ADDONS_FIXTURE/custom/ventas/__manifest__.py" \
  "$ADDONS_FIXTURE/enterprise/enterprise_mod/__manifest__.py"
printf '%040d\n' 1 > "$ADDONS_FIXTURE/custom/ventas/.candidate-commit"
printf '%040d\n' 2 > "$ADDONS_FIXTURE/custom/ventas/.candidate-tree"
mkdir -p "$ADDONS_FIXTURE/enterprise/.git"
printf '%040d\n' 3 > "$ADDONS_FIXTURE/enterprise/.git/HEAD"
printf '[options]\n' > "$ROOT/config/odoo.conf"
printf 'admin\n' > "$ROOT/secrets/odoo_admin_password"
printf 'postgres\n' > "$ROOT/secrets/postgres_password"
: > "$ROOT/secrets/zeptomail_smtp_password"
sed -e "s#ADDONS_BASE=/opt/odoo#ADDONS_BASE=$ADDONS_FIXTURE#" \
  -e "s#RUNTIME_CONF=/tmp/odoo-runtime.conf#RUNTIME_CONF=$RUNTIME_CONF_FIXTURE#" \
  -e "s#STARTUP_INVENTORY=/tmp/odoo-addons-startup.json#STARTUP_INVENTORY=$ROOT/odoo-addons-startup.json#" \
  -e "s#/etc/odoo/odoo.conf#$ROOT/config/odoo.conf#g" \
  -e "s#/run/secrets#$ROOT/secrets#g" \
  "$REPO_ROOT/stacks/odoo/image/entrypoint.sh" > "$ENTRYPOINT"
chmod 755 "$ENTRYPOINT"
cat > "$TMP/bin/odoo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 755 "$TMP/bin/odoo"

salida=$(ENTORNO=produccion TAG=19.0-ce-2026-09-18 ODOO_EDITION=community ODOO_COMMUNITY_ADDONS="$ROOT/community" "$ENTRYPOINT" --stop-after-init 2>&1); codigo=$?
igual "Community arranca aunque exista un árbol Enterprise residual" 0 "$codigo"
no_contiene "Community excluye Enterprise del addons_path" "$ADDONS_FIXTURE/enterprise" "$(cat "$RUNTIME_CONF_FIXTURE")"
contiene "Community conserva custom en addons_path" "$ADDONS_FIXTURE/custom/ventas" "$(cat "$RUNTIME_CONF_FIXTURE")"
igual "registra el entorno cargado" "produccion" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["entorno"])' "$ROOT/odoo-addons-startup.json")"
igual "registra el commit custom cargado" "$(printf '%040d' 1)" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["addons"]["ventas"]["commit"])' "$ROOT/odoo-addons-startup.json")"
igual "registra la huella custom cargada" "$(printf '%040d' 2)" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["addons"]["ventas"]["tree"])' "$ROOT/odoo-addons-startup.json")"
igual "Community registra Enterprise ausente" "None" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["enterprise"])' "$ROOT/odoo-addons-startup.json")"

salida=$(ENTORNO=produccion TAG=19.0-ee-2026-09-18 ODOO_EDITION=enterprise ODOO_COMMUNITY_ADDONS="$ROOT/community" "$ENTRYPOINT" --stop-after-init 2>&1); codigo=$?
igual "Enterprise arranca con su árbol seleccionado" 0 "$codigo"
contiene "Enterprise precede custom en addons_path" \
  "addons_path = $ADDONS_FIXTURE/enterprise,$ADDONS_FIXTURE/custom/ventas,$ROOT/community" \
  "$(cat "$RUNTIME_CONF_FIXTURE")"
igual "registra el commit Enterprise cargado" "$(printf '%040d' 3)" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["enterprise"]["commit"])' "$ROOT/odoo-addons-startup.json")"

rm "$ADDONS_FIXTURE/enterprise/enterprise_mod/__manifest__.py"
salida=$(ENTORNO=produccion TAG=19.0-ee-2026-09-18 ODOO_EDITION=enterprise ODOO_COMMUNITY_ADDONS="$ROOT/community" "$ENTRYPOINT" --stop-after-init 2>&1); codigo=$?
igual "Enterprise falla con un checkout vacío" 1 "$codigo"
contiene "Enterprise explica el árbol faltante" "árbol Enterprise está vacío" "$salida"

resumen
