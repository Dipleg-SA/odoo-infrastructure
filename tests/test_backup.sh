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
printf '%s\n' 'rama declarada: 19.0' 'custom-addons ventas 19.0 abc123 limpio'
EOF

igual "un registro válido deja exitoso el backup" "0" "$(codigo_backup "$ROOT")"
igual "guarda solo las filas de worktrees" "custom-addons ventas 19.0 abc123 limpio" \
  "$(cat "$ROOT/state/meta/addons.txt")"
igual "guarda la procedencia de imágenes" "0" "$([ -s "$ROOT/state/meta/images.json" ] && grep -q '"Actual"' "$ROOT/state/meta/images.json"; echo $?)"
contiene "restore reaplica la procedencia de imágenes" "restore-meta" "$(cat "$REPO_ROOT/stacks/backup/scripts/restore.sh")"
contiene "backup monta metadatos del runtime" "RUNTIME_STATE_DIR" "$(cat "$REPO_ROOT/stacks/backup/compose.yaml")"

resumen
