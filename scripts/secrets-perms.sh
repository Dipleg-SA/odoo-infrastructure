#!/usr/bin/env bash
# Permisos y grupo de secrets/. Único dueño del mapa de GIDs: --apply lo escribe,
# --check lo valida, así que no hay dos copias que se desincronicen.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

SECRETS_DIR="secrets"
EXPECTED_PERMS="640"
MARK="CAMBIAR"

# --- Mapeo secret -> GID esperado ---
# GID del proceso NO-ROOT que lee cada secret; vacío = sin GID requerido.

expected_gid_for() {
  case "$1" in
    cloudflare_api_token) echo "" ;;           # lo lee certbot, que corre como root — sin GID que exigir
    cloudflare_tunnel_token) echo "65532" ;;   # cloudflared non-root (65532:65532, distroless) — load-bearing
    postgres_password) echo "101" ;;           # lo lee odoo non-root (gid 101); postgres lo lee como root — load-bearing por odoo
    odoo_admin_password) echo "101" ;;           # odoo non-root (100:101) — load-bearing
    zeptomail_smtp_password) echo "101" ;;     # odoo non-root (100:101); grafana lo alcanza por group_add — load-bearing
    grafana_admin_password) echo "472" ;;      # grafana corre 472:0, así que el 472 le llega por group_add, no por gid primario — load-bearing
    postgres_exporter_password) echo "" ;;     # lo lee alloy, que corre como root — sin GID que exigir
    restic_password) echo "101" ;;             # restic corre con los uid/gid de odoo (100:101) — load-bearing
    restic_r2_credentials) echo "101" ;;       # ídem — load-bearing
    *) echo "" ;;                              # fallback genérico — no debería alcanzarse, todos los secrets están listados arriba
  esac
}

# --- stat portable (GNU/BSD) ---
# Linux usa 'stat -c'; macOS/BSD usa 'stat -f'. Prueba GNU primero y cae al otro.

get_stat() {
  if stat -c '%a %g' "$1" >/dev/null 2>&1; then
    stat -c '%a %g' "$1"
  else
    stat -f '%Lp %g' "$1"
  fi
}

# --- Directorio ---
# Sin secrets/ no hay nada que hacer; secrets-init lo crea.

if [ ! -d "$SECRETS_DIR" ]; then
  ui_bad "$SECRETS_DIR no existe" "correr 'make secrets-init' primero" >&2
  exit 1
fi

MODE="${1:---check}"

# --- Aplicar ---
# chmod a todos; chgrp solo a los mapeados. El chgrp a un GID ajeno exige root.

if [ "$MODE" = "--apply" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    ui_bad "secrets-perms --apply requiere root" "chgrp a un GID del que no sos miembro — corré: sudo make secrets-perms" >&2
    exit 1
  fi
  ui_start "secrets-perms --apply"
  for file in "$SECRETS_DIR"/*; do
    [ -f "$file" ] || continue
    chmod "$EXPECTED_PERMS" "$file"
    gid="$(expected_gid_for "$(basename "$file")")"
    [ -n "$gid" ] && chgrp "$gid" "$file"
    echo "  $(basename "$file"): $EXPECTED_PERMS${gid:+ / gid $gid}"
  done
  ui_ok "secrets-perms --apply listo"
  exit 0
fi

if [ "$MODE" != "--check" ]; then
  ui_bad "uso: $(basename "$0") [--check|--apply]" "" >&2
  exit 2
fi

# --- Verificar ---
# Permisos en todos, GID en los mapeados, y que no quede ningún marcador sin cargar.

ui_start "secrets-perms --check"
fail=0
for file in "$SECRETS_DIR"/*; do
  [ -f "$file" ] || continue
  name="$(basename "$file")"
  expected_gid="$(expected_gid_for "$name")"
  read -r actual_perms actual_gid <<< "$(get_stat "$file")"

  if [ "$actual_perms" != "$EXPECTED_PERMS" ]; then
    ui_bad "$file" "permisos $actual_perms, esperado $EXPECTED_PERMS" >&2
    fail=1
  fi
  if [ -n "$expected_gid" ] && [ "$actual_gid" != "$expected_gid" ]; then
    ui_bad "$file" "grupo $actual_gid, esperado $expected_gid" >&2
    fail=1
  fi
  if grep -q "$MARK" "$file" 2>/dev/null; then
    ui_bad "$file" "todavía tiene el marcador $MARK, falta el valor real" >&2
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then ui_ok "secrets-perms --check listo"
else ui_bad "secrets-perms --check falló" "" >&2; fi

exit "$fail"
