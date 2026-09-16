#!/usr/bin/env bash
# --- Backup diario ---
# Prueba que un inventario de addons fallido se diagnostica sin afectar el snapshot.

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
STUB_DIR="$TMP/stub"; mkdir -p "$STUB_DIR"; export STUB_DIR
trap 'rm -rf "$TMP"' EXIT

# --- Checkout mínimo ---
# Solo contiene las rutas que toca backup.sh y usa el stub compartido de Docker.

crear_checkout() {
  local root="$TMP/backup"
  mkdir -p "$root/stacks/backup/scripts" "$root/stacks/backup/config" \
           "$root/scripts/lib" "$root/scripts" "$root/state/meta"
  cp "$REPO_ROOT/stacks/backup/scripts/backup.sh" "$root/stacks/backup/scripts/"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$root/scripts/lib/"
  printf '%s\n' 'RESTIC_REPOSITORY=s3:https://cuenta.r2.cloudflarestorage.com/bucket/restic' \
    > "$root/stacks/backup/config/r2.env"
  printf '%s' "$root"
}

ejecutar_backup() {
  (cd "$1" && PATH="$REPO_ROOT/tests/stubs:$PATH" ./stacks/backup/scripts/backup.sh daily 2>&1)
}

codigo_backup() {
  (cd "$1" && PATH="$REPO_ROOT/tests/stubs:$PATH" ./stacks/backup/scripts/backup.sh daily >/dev/null 2>&1; echo $?)
}

definir_addons() {
  cat > "$1/scripts/addons.sh"
  chmod 755 "$1/scripts/addons.sh"
}

# =====================================================================
titulo "backup.sh — registro de addons best-effort"
# =====================================================================

ROOT=$(crear_checkout)
printf 'inventario anterior\n' > "$ROOT/state/meta/addons.txt"

# --- Fallo informado ---
# El backup conserva el inventario previo y el error de addons queda visible.

definir_addons "$ROOT" <<'EOF'
#!/usr/bin/env bash
echo 'fallo de git simulado' >&2
exit 7
EOF

igual "un fallo de addons no falla el backup" "0" "$(codigo_backup "$ROOT")"
contiene "conserva el diagnóstico de addons" "fallo de git simulado" "$(ejecutar_backup "$ROOT")"
contiene "y conserva su código de salida" "salió con 7" "$(ejecutar_backup "$ROOT")"
igual "no pisa el inventario anterior" "inventario anterior" "$(cat "$ROOT/state/meta/addons.txt")"

# --- Registro válido ---
# La salida se filtra al formato del snapshot y reemplaza el inventario en forma atómica.

definir_addons "$ROOT" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'runtime: produccion · rama: 19.0' 'enterprise: 19.0-ee-2026-09-15 · commit: ee123' 'dominio_ventas publicado abc123'
EOF

igual "un registro válido deja exitoso el backup" "0" "$(codigo_backup "$ROOT")"
contiene "guarda el estado de Enterprise" "enterprise: 19.0-ee-2026-09-15 · commit: ee123" \
  "$(cat "$ROOT/state/meta/addons.txt")"
contiene "guarda el commit del candidato" "dominio_ventas publicado abc123" \
  "$(cat "$ROOT/state/meta/addons.txt")"
igual "guarda la procedencia de imágenes" "0" "$([ -s "$ROOT/state/meta/images.json" ] && grep -q '"Actual"' "$ROOT/state/meta/images.json"; echo $?)"
contiene "restore reaplica la procedencia de imágenes" "restore-meta" "$(cat "$REPO_ROOT/stacks/backup/scripts/restore.sh")"
contiene "backup monta metadatos del runtime" "RUNTIME_STATE_DIR" "$(cat "$REPO_ROOT/stacks/backup/compose.yaml")"

# =====================================================================
titulo "backup.sh — contexto del runtime"
# =====================================================================

ROOT="$TMP/backup-context"
mkdir -p "$ROOT/stacks/backup/scripts" "$ROOT/stacks/backup/config" \
         "$ROOT/scripts/lib" "$ROOT/scripts" "$ROOT/runtime/produccion/state/meta"
ROOT="$(cd "$ROOT" && pwd -P)"
cp "$REPO_ROOT/stacks/backup/scripts/backup.sh" "$ROOT/stacks/backup/scripts/"
cp "$REPO_ROOT/scripts/lib/ui.sh" "$REPO_ROOT/scripts/lib/contexto.sh" "$ROOT/scripts/lib/"
cp "$REPO_ROOT/stacks/backup/scripts/restore.sh" "$ROOT/stacks/backup/scripts/"
cp "$REPO_ROOT/scripts/image-state.sh" "$ROOT/scripts/"
chmod 755 "$ROOT/stacks/backup/scripts/restore.sh" "$ROOT/scripts/image-state.sh"
printf 'services: {}\n' > "$ROOT/runtime/produccion/compose.yaml"
printf 'COMPOSE_PROJECT_NAME=backup-context\nODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' \
  > "$ROOT/runtime/produccion/compose.env"
python3 - "$ROOT/runtime/produccion/state/images.json" <<'PY'
import json, sys

community = {
    'tag': 'local/odoo:community', 'digest': 'sha256:ce', 'odoo_version': '19.0',
    'base_image': 'odoo:19.0', 'infra_commit': 'infra', 'edition': 'community',
    'edition_tag': '19.0-ce-2026-09-16', 'enterprise_tag': None,
    'enterprise_commit': None, 'enterprise_modules': [], 'addons': {},
    'built_at': '2026-09-16T00:00:00Z',
}
json.dump({'Nueva': None, 'Actual': community, 'Anterior': None,
           'validation': None, 'rollback_blocked': False, 'module_operations': []},
          open(sys.argv[1], 'w', encoding='utf-8'))
PY
printf '%s\n' 'RESTIC_REPOSITORY=s3:https://cuenta.r2.cloudflarestorage.com/bucket/restic' \
  > "$ROOT/stacks/backup/config/r2.env"
printf '%s\n' '{"message_type":"summary","snapshot_id":"snap-context"}' > "$STUB_DIR/salida"
definir_addons "$ROOT" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'dominio_ventas publicado abc123'
EOF
(cd "$ROOT" && STUB_DIR="$STUB_DIR" ENTORNO=produccion PATH="$REPO_ROOT/tests/stubs:$PATH" \
  ./stacks/backup/scripts/backup.sh daily >/dev/null 2>&1)
igual "el backup con contexto usa la composición del entorno" "0" \
  "$(grep -F -- "-f $ROOT/runtime/produccion/compose.yaml" "$STUB_DIR/llamadas" >/dev/null; echo $?)"
igual "la marca de éxito cae en el estado del entorno" "0" \
  "$([ -s "$ROOT/runtime/produccion/state/textfile/backup-daily.prom" ] && [ ! -e "$ROOT/state/textfile/backup-daily.prom" ]; echo $?)"
contiene "backup conserva la edición Community" '"edition": "community"' \
  "$(cat "$ROOT/runtime/produccion/state/meta/images.json")"
contiene "backup conserva el tag Community" '"edition_tag": "19.0-ce-2026-09-16"' \
  "$(cat "$ROOT/runtime/produccion/state/meta/images.json")"

mkdir -p "$STUB_DIR/restore-bin"
cat > "$STUB_DIR/restore-bin/docker" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *" ps -q odoo"*) exit 0 ;;
  *" ps -q postgres"*) printf '%s\n' postgres-id; exit 0 ;;
esac
exec "$REPO_ROOT/tests/stubs/docker" "\$@"
EOF
chmod 755 "$STUB_DIR/restore-bin/docker"
salida=$(cd "$ROOT" && STUB_DIR="$STUB_DIR" ENTORNO=produccion \
  PATH="$STUB_DIR/restore-bin:$REPO_ROOT/tests/stubs:$PATH" \
  ./stacks/backup/scripts/restore.sh snap-context 2>&1); codigo=$?
igual "restore Community exitoso" 0 "$codigo"
contiene "restore conserva la edición Community" '"edition": "community"' \
  "$(cat "$ROOT/runtime/produccion/state/images.json")"
contiene "restore conserva el tag Community" '"edition_tag": "19.0-ce-2026-09-16"' \
  "$(cat "$ROOT/runtime/produccion/state/images.json")"
no_contiene "restore no recupera código Enterprise" "enterprise" "$(cat "$STUB_DIR/llamadas")"

resumen
