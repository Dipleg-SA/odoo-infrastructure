#!/bin/bash
set -e
shopt -s nullglob

ADDONS_BASE=/opt/odoo
RUNTIME_CONF=/tmp/odoo-runtime.conf

# addons_path interno
# Enterprise precede dominios propios y Community cierra la precedencia.

paths=()
[ -d "$ADDONS_BASE/enterprise" ] && paths+=("$ADDONS_BASE/enterprise")
for repo in "$ADDONS_BASE/custom"/*/; do
  [ -d "$repo" ] && paths+=("${repo%/}")
done
COMMUNITY_ADDONS="${ODOO_COMMUNITY_ADDONS:-/usr/lib/python3/dist-packages/odoo/addons}"
[ -d "$COMMUNITY_ADDONS" ] && paths+=("$COMMUNITY_ADDONS")
ADDONS_PATH=$(IFS=,; echo "${paths[*]}")

if [ "${#paths[@]}" -eq 0 ]; then
  echo "odoo-entrypoint: addons_path vacío — ¿corriste make repo-sync antes de levantar el stack?" >&2
  exit 1
fi

# --- Config runtime: base + addons_path + secrets inyectados ---

cp /etc/odoo/odoo.conf "$RUNTIME_CONF"
{
  echo "addons_path = ${ADDONS_PATH}"
  echo "admin_passwd = $(cat /run/secrets/odoo_admin_password)"
  # server/port/user vienen de .env (SMTP_HOST/SMTP_PORT/SMTP_USER), igual que
  # admin_passwd viene del secret: un solo lugar donde cargarlos, no un literal
  # en odoo.conf que haya que mantener igual a mano. Respaldo estructural: si
  # ODOO_DISABLE_SMTP=1, gana esta rama y sale vacío pase lo que pase en .env —
  # última línea gana, así que pisa lo que se haya escrito arriba.
  if [ "${ODOO_DISABLE_SMTP:-}" = "1" ]; then
    echo "smtp_server = "
  else
    [ -n "${SMTP_HOST:-}" ] && echo "smtp_server = ${SMTP_HOST}"
    [ -n "${SMTP_PORT:-}" ] && echo "smtp_port = ${SMTP_PORT}"
    [ -n "${SMTP_USER:-}" ] && echo "smtp_user = ${SMTP_USER}"
  fi
  if [ -s /run/secrets/zeptomail_smtp_password ]; then
    echo "smtp_password = $(cat /run/secrets/zeptomail_smtp_password)"
  fi
} >> "$RUNTIME_CONF"

# --- Password para conexión directa a postgres (usado en el init check y en el modo one-off) ---

DB_PASSWORD="$(cat /run/secrets/postgres_password)"

# --- Modo one-off: operaciones explícitas del operador (make addons-*) ---
# Conexión explícita, no heredada de HOST/PORT: corre antes de que el entrypoint oficial arme su propia espera.

if [ "$#" -gt 0 ]; then
  # `shell` es un subcomando de Odoo, no un flag del servidor. Mantenerlo
  # después de `odoo` evita que el entrypoint lo convierta en un parámetro
  # inválido y conserva el mismo runtime conf y conexión que los one-off.
  if [ "${1:-}" = "shell" ]; then
    shift
    exec odoo shell -c "$RUNTIME_CONF" -d odoo --no-http "$@" \
      --db_host=postgres --db_port=5432 --db_user=odoo --db_password="$DB_PASSWORD"
  fi

  exec odoo -c "$RUNTIME_CONF" -d odoo --no-http "$@" \
    --db_host=postgres --db_port=5432 --db_user=odoo --db_password="$DB_PASSWORD"
fi

# --- Init check: directo a postgres:5432 ---
# Transaction mode no soporta advisory locks/DDL; dispara si NO está inicializada (ir_module_module).

INITIALIZED=$(PGPASSWORD="$DB_PASSWORD" psql -h postgres -p 5432 -U odoo -d odoo -tAc \
  "SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module'" 2>/dev/null || true)

if [ "$INITIALIZED" != "1" ]; then
  echo "odoo-entrypoint: base 'odoo' no inicializada — corriendo -i base (directo a postgres:5432)"
  odoo -c "$RUNTIME_CONF" -d odoo -i base --stop-after-init --no-http \
    --db_host=postgres --db_port=5432 --db_user=odoo --db_password="$DB_PASSWORD"
fi

# --- Entrypoint oficial: wait-for-psql + --db_host/etc hacia postgres ---

exec /entrypoint.sh odoo -c "$RUNTIME_CONF"
