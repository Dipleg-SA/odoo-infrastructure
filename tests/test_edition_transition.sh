#!/usr/bin/env bash
# Contrato de transición Community a Enterprise
# Verifica el preflight ORM, el backup asociado y la ausencia de operaciones funcionales automáticas.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
ROOT="$TMP/repo"
mkdir -p "$ROOT/scripts/lib" "$ROOT/scripts" "$ROOT/runtime/produccion/state/meta" \
  "$ROOT/runtime/produccion/config" "$ROOT/stacks/backup/scripts" \
  "$ROOT/stacks/backup/config" "$TMP/bin"
export STUB_DIR="$TMP"
export PATH="$TMP/bin:$REPO_ROOT/tests/stubs:$PATH"
trap 'rm -rf "$TMP"' EXIT

cp scripts/lib/contexto.sh scripts/image-state.sh scripts/odoo-edition-check.sh scripts/lib/ui.sh \
  "$ROOT/scripts/"
cp scripts/lib/contexto.sh scripts/lib/ui.sh "$ROOT/scripts/lib/"
cp stacks/backup/scripts/backup.sh "$ROOT/stacks/backup/scripts/"
chmod 755 "$ROOT/scripts/image-state.sh" "$ROOT/scripts/odoo-edition-check.sh" \
  "$ROOT/stacks/backup/scripts/backup.sh"

cat > "$ROOT/runtime/produccion/compose.yaml" <<'EOF'
services: {}
EOF
cat > "$ROOT/stacks/backup/config/r2.env" <<'EOF'
RESTIC_REPOSITORY=s3:https://cuenta.r2.cloudflarestorage.com/bucket/restic
EOF

cat > "$TMP/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/llamadas"
case "$*" in
  *"run --rm --name odoo-edition-check"*)
    printf '%s\n' 'ODOO_EDITION_CHECK_MODULES=base,ventas'
    ;;
  *"restic backup --json"*)
    printf '%s\n' '{"message_type":"summary","snapshot_id":"snap-transition-1"}'
    ;;
esac
DOCKER
chmod 755 "$TMP/bin/docker"

cat > "$ROOT/scripts/addons.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'ventas publicado abc123'
EOF
chmod 755 "$ROOT/scripts/addons.sh"

escribir_entorno() {
  local edition="$1" tag="$2"
  printf '%s\n' "COMPOSE_PROJECT_NAME=transition-test" \
    "ODOO_EDITION=$edition" "TAG=$tag" "ODOO_IMAGE=local/odoo:community" \
    > "$ROOT/runtime/produccion/compose.env"
}

escribir_estado() {
  python3 - "$ROOT/runtime/produccion/state/images.json" <<'PY'
import json, sys

community = {
    'tag': 'local/odoo:community', 'digest': 'sha256:ce', 'odoo_version': '19.0',
    'base_image': 'odoo:19.0', 'infra_commit': 'infra', 'edition': 'community',
    'edition_tag': '19.0-ce-2026-09-16', 'enterprise_tag': None,
    'enterprise_commit': None, 'enterprise_modules': [], 'addons': {'ventas': 'abc'},
    'built_at': '2026-09-16T00:00:00Z',
}
enterprise = dict(community)
enterprise.update({
    'tag': 'local/odoo:enterprise', 'edition': 'enterprise',
    'edition_tag': '19.0-ee-2026-09-16', 'enterprise_tag': '19.0-ee-2026-09-16',
    'enterprise_commit': 'ee', 'enterprise_modules': ['ventas'],
})
json.dump({'Nueva': enterprise, 'Actual': community, 'Anterior': None,
           'validation': None, 'rollback_blocked': False, 'module_operations': []},
          open(sys.argv[1], 'w', encoding='utf-8'))
PY
}

titulo "odoo-edition-check.sh — lectura ORM"
escribir_entorno community 19.0-ce-2026-09-16
escribir_estado
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/odoo-edition-check.sh --destino enterprise 2>&1); codigo=$?
igual "preflight Community a Enterprise es compatible" 0 "$codigo"
contiene "informa módulos instalados" "módulos instalados: base,ventas" "$salida"
contiene "usa Odoo shell" "odoo shell --no-http" "$(cat "$TMP/llamadas")"

titulo "backup.sh — snapshot asociado"
salida=$(cd "$ROOT" && ENTORNO=produccion ./stacks/backup/scripts/backup.sh daily 2>&1); codigo=$?
igual "backup productivo exitoso" 0 "$codigo"
igual "registra el snapshot" "snap-transition-1" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["snapshot_id"])' "$ROOT/runtime/produccion/state/meta/last-backup.json")"
igual "asocia la edición respaldada" "community" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["edition"])' "$ROOT/runtime/produccion/state/meta/last-backup.json")"
igual "asocia la imagen Actual" "local/odoo:community" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["actual_tag"])' "$ROOT/runtime/produccion/state/meta/last-backup.json")"
igual "no deja temporal de metadata" "0" "$([ -z "$(find "$ROOT/runtime/produccion/state/meta" -name '.last-backup.*' -print -quit)" ] && echo 0 || echo 1)"

titulo "image-state.sh — aplicación controlada"
escribir_entorno enterprise 19.0-ee-2026-09-16
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/image-state.sh apply 2>&1); codigo=$?
igual "aplica Community a Enterprise con backup" 0 "$codigo"
contiene "registra la edición destino" '"edition": "enterprise"' \
  "$(cat "$ROOT/runtime/produccion/state/images.json")"
igual "conserva la imagen Community como Anterior" "local/odoo:community" \
  "$(cd "$ROOT" && ENTORNO=produccion scripts/image-state.sh get Anterior | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
igual "preserva módulos instalados sin operación funcional" "0" \
  "$(if grep -q 'ODOO_OPERATION\|button_immediate\|update_list' "$TMP/llamadas"; then echo 1; else echo 0; fi)"

titulo "odoo-edition-check.sh — bloqueo conservador"
python3 - "$ROOT/runtime/produccion/state/images.json" <<'PY'
import json, sys

path = sys.argv[1]
state = json.load(open(path, encoding='utf-8'))
state['Nueva'] = None
json.dump(state, open(path, 'w', encoding='utf-8'))
PY
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/odoo-edition-check.sh --destino community 2>&1); codigo=$?
igual "bloquea Community con módulo Enterprise instalado" 1 "$codigo"
contiene "informa el módulo incompatible" "ventas" "$salida"

titulo "image-state.sh — backup obligatorio"
escribir_estado
rm -f "$ROOT/runtime/produccion/state/meta/last-backup.json"
salida=$(cd "$ROOT" && ENTORNO=produccion scripts/image-state.sh apply 2>&1); codigo=$?
igual "bloquea transición sin backup asociado" 1 "$codigo"
igual "conserva Actual ante el bloqueo" "local/odoo:community" \
  "$(cd "$ROOT" && ENTORNO=produccion scripts/image-state.sh get Actual | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"

resumen
