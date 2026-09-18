#!/usr/bin/env bash
# --- Backup diario ---
# Prueba que un inventario de addons fallido se diagnostica sin afectar el snapshot.

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
STUB_DIR="$TMP/stub"; mkdir -p "$STUB_DIR"; export STUB_DIR
printf '%s\n' '{"snapshot_id":"snap-test"}' > "$STUB_DIR/salida"
trap 'rm -rf "$TMP"' EXIT

# --- Checkout mínimo ---
# Solo contiene las rutas que toca backup.sh y usa el stub compartido de Docker.

crear_checkout() {
  local root="$TMP/backup"
  mkdir -p "$root/stacks/backup/scripts" "$root/stacks/backup/config" \
           "$root/scripts/lib" "$root/scripts" "$root/runtime/desarrollo/state/meta"
  cp "$REPO_ROOT/stacks/backup/scripts/backup.sh" "$root/stacks/backup/scripts/"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$REPO_ROOT/scripts/lib/contexto.sh" "$root/scripts/lib/"
  printf '%s\n' 'services: {}' > "$root/runtime/desarrollo/compose.yaml"
  printf '%s\n' \
    'COMPOSE_PROJECT_NAME=backup-test' \
    'ODOO_EDITION=community' \
    'TAG=19.0-ce-2026-09-16' \
    'ODOO_IMAGE=local/odoo:19.0-desarrollo-20260917T183719Z-fa588059f4932d2f' \
    > "$root/runtime/desarrollo/compose.env"
  printf '%s\n' 'RESTIC_REPOSITORY=s3:https://cuenta.r2.cloudflarestorage.com/bucket/restic' \
    > "$root/stacks/backup/config/r2.env"
  printf '%s' "$root"
}

ejecutar_backup() {
  (cd "$1" && ENTORNO=desarrollo PATH="$REPO_ROOT/tests/stubs:$PATH" ./stacks/backup/scripts/backup.sh daily 2>&1)
}

codigo_backup() {
  (cd "$1" && ENTORNO=desarrollo PATH="$REPO_ROOT/tests/stubs:$PATH" ./stacks/backup/scripts/backup.sh daily >/dev/null 2>&1; echo $?)
}

definir_addons() {
  cat > "$1/scripts/addons.sh"
  chmod 755 "$1/scripts/addons.sh"
}

# =====================================================================
titulo "backup.sh — registro de addons best-effort"
# =====================================================================

ROOT=$(crear_checkout)
printf 'inventario anterior\n' > "$ROOT/runtime/desarrollo/state/meta/addons.txt"

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
igual "no pisa el inventario anterior" "inventario anterior" "$(cat "$ROOT/runtime/desarrollo/state/meta/addons.txt")"

# --- Entorno obligatorio ---
# Una invocación directa sin entorno falla antes de crear estado global.

salida=$(cd "$ROOT" && PATH="$REPO_ROOT/tests/stubs:$PATH" ./stacks/backup/scripts/backup.sh daily 2>&1); codigo=$?
igual "backup sin entorno falla antes de operar" "2" "$codigo"
contiene "backup sin entorno informa la corrección" "usar ENTORNO=desarrollo, staging o produccion" "$salida"
igual "backup sin entorno no crea estado raíz" "0" "$([ ! -e "$ROOT/state" ]; echo $?)"

# --- Registro válido ---
# La salida se filtra al formato del snapshot y reemplaza el inventario en forma atómica.

definir_addons "$ROOT" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'runtime: produccion · rama: 19.0' 'enterprise: 19.0-ee-2026-09-15 · commit: ee123' 'dominio_ventas publicado abc123'
EOF

igual "un registro válido deja exitoso el backup" "0" "$(codigo_backup "$ROOT")"
contiene "guarda el estado de Enterprise" "enterprise: 19.0-ee-2026-09-15 · commit: ee123" \
  "$(cat "$ROOT/runtime/desarrollo/state/meta/addons.txt")"
contiene "guarda el commit del candidato" "dominio_ventas publicado abc123" \
  "$(cat "$ROOT/runtime/desarrollo/state/meta/addons.txt")"
contiene "registra el selector como metadata de backup" '"odoo_image": "local/odoo:19.0-desarrollo-20260917T183719Z-fa588059f4932d2f"' \
  "$(cat "$ROOT/runtime/desarrollo/state/meta/last-backup.json")"
no_contiene "no registra actual_tag" '"actual_tag"' \
  "$(cat "$ROOT/runtime/desarrollo/state/meta/last-backup.json")"
igual "no crea metadata de slots de imagen" "0" \
  "$([ ! -e "$ROOT/runtime/desarrollo/state/meta/images.json" ]; echo $?)"
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
printf 'services: {}\n' > "$ROOT/runtime/produccion/compose.yaml"
printf 'COMPOSE_PROJECT_NAME=backup-context\nODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\nODOO_IMAGE=local/odoo:19.0-produccion-20260917T183719Z-fa588059f4932d2f\n' \
  > "$ROOT/runtime/produccion/compose.env"
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

# --- Restore tolerante a metadata legacy ---
# Recuperar metadata histórica no debe seleccionar ni validar una imagen.
cp "$REPO_ROOT/stacks/backup/scripts/restore.sh" "$ROOT/stacks/backup/scripts/"
mkdir -p "$TMP/restore-bin"
cat > "$TMP/restore-bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_DIR/restore-llamadas"
case "\$*" in
  *"ps -q odoo"*) exit 0 ;;
  *"ps -q postgres"*) printf '%s\n' postgres-id; exit 0 ;;
  *"--entrypoint restic"*"/data/meta"*)
    mkdir -p "$ROOT/runtime/produccion/state/meta"
    printf '%s\n' '{"Actual":"legacy"}' > "$ROOT/runtime/produccion/state/meta/images.json"
    printf '%s\n' '{"snapshot_id":"snap-context","odoo_image":"legacy"}' > "$ROOT/runtime/produccion/state/meta/last-backup.json"
    ;;
esac
exit 0
EOF
chmod 755 "$TMP/restore-bin/docker"
salida=$(cd "$ROOT" && STUB_DIR="$STUB_DIR" ENTORNO=produccion \
  PATH="$TMP/restore-bin:$PATH" ./stacks/backup/scripts/restore.sh snap-context 2>&1); codigo=$?
igual "restore tolera metadata legacy" 0 "$codigo"
contiene "restore recupera metadata de backup" '"snapshot_id":"snap-context"' \
  "$(cat "$ROOT/runtime/produccion/state/meta/last-backup.json")"
no_contiene "restore no ejecuta image-state" "image-state" "$(cat "$STUB_DIR/restore-llamadas")"
igual "restore no cambia el selector del entorno" \
  "local/odoo:19.0-produccion-20260917T183719Z-fa588059f4932d2f" \
  "$(sed -n 's/^ODOO_IMAGE=//p' "$ROOT/runtime/produccion/compose.env")"

resumen
