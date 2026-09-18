#!/bin/bash
set -e
shopt -s nullglob

ADDONS_BASE=/opt/odoo
RUNTIME_CONF=/tmp/odoo-runtime.conf
STARTUP_INVENTORY=/tmp/odoo-addons-startup.json

# addons_path interno
# Un Enterprise con manifiestos precede dominios propios y Community cierra la precedencia.

paths=()
# Selección de edición
# Community ignora residuos Enterprise y Enterprise exige un árbol con manifiestos.
case "${ODOO_EDITION:-}" in
  community) ;;
  enterprise)
    if [ -n "$(find "$ADDONS_BASE/enterprise" -name __manifest__.py -type f -print -quit 2>/dev/null)" ]; then
      paths+=("$ADDONS_BASE/enterprise")
    else
      echo "odoo-entrypoint: ODOO_EDITION=enterprise pero el árbol Enterprise está vacío" >&2
      exit 1
    fi
    ;;
  *)
    echo "odoo-entrypoint: ODOO_EDITION debe ser community o enterprise" >&2
    exit 2
    ;;
esac
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

# Selección cargada al arranque
# Persiste los marcadores que este proceso vio antes de delegar el inicio a Odoo.
python3 - "$ADDONS_BASE" "$STARTUP_INVENTORY" "${ENTORNO:-}" "${ODOO_EDITION:-}" "${TAG:-}" <<'PY'
import json
import os
import pathlib
import sys
import tempfile

root_arg, output_arg, environment, edition, tag = sys.argv[1:]
root = pathlib.Path(root_arg)
output = pathlib.Path(output_arg)
if environment not in {"desarrollo", "staging", "produccion"}:
    print("odoo-entrypoint: ENTORNO debe identificar el runtime cargado", file=sys.stderr)
    raise SystemExit(2)

addons = {}
for candidate in sorted((root / "custom").glob("*")):
    if not candidate.is_dir():
        continue
    try:
        commit = (candidate / ".candidate-commit").read_text(encoding="ascii").strip()
        tree = (candidate / ".candidate-tree").read_text(encoding="ascii").strip()
    except OSError:
        print(f"odoo-entrypoint: faltan marcadores en {candidate}", file=sys.stderr)
        raise SystemExit(1)
    if not commit or not tree:
        print(f"odoo-entrypoint: marcadores vacíos en {candidate}", file=sys.stderr)
        raise SystemExit(1)
    addons[candidate.name] = {"commit": commit, "tree": tree}

enterprise = None
if edition == "enterprise":
    head = root / "enterprise" / ".git" / "HEAD"
    try:
        commit = head.read_text(encoding="ascii").strip()
    except OSError:
        print("odoo-entrypoint: Enterprise no expone el commit cargado", file=sys.stderr)
        raise SystemExit(1)
    if commit.startswith("ref:") or not commit:
        print("odoo-entrypoint: Enterprise debe estar en HEAD separado", file=sys.stderr)
        raise SystemExit(1)
    enterprise = {"tag": tag, "commit": commit}

payload = {
    "entorno": environment,
    "edition": edition,
    "addons": addons,
    "enterprise": enterprise,
}
fd, temporary = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(payload, stream, ensure_ascii=False, sort_keys=True)
        stream.write("\n")
    os.replace(temporary, output)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY

# --- Config runtime: base + addons_path + secrets inyectados ---
# Construye el archivo temporal que consume Odoo.

cp /etc/odoo/odoo.conf "$RUNTIME_CONF"
{
  echo "addons_path = ${ADDONS_PATH}"
  echo "admin_passwd = $(cat /run/secrets/odoo_admin_password)"
  # server/port/user vienen de compose.env (SMTP_HOST/SMTP_PORT/SMTP_USER), igual que
  # admin_passwd del secret; ODOO_DISABLE_SMTP fuerza un smtp_server vacío.
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
# Se reutiliza para el chequeo inicial y las operaciones explícitas.

DB_PASSWORD="$(cat /run/secrets/postgres_password)"

# --- Modo one-off: operaciones explícitas del operador (make addons-*) ---
# Conexión explícita, no heredada de HOST/PORT: corre antes de que el entrypoint oficial arme su propia espera.

if [ "$#" -gt 0 ]; then
  # `shell` es un subcomando de Odoo, no un flag del servidor. Mantenerlo
  # después de `odoo` conserva el runtime conf y la conexión de los one-off.
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
# Delega la espera final y el arranque normal en la imagen oficial.

exec /entrypoint.sh odoo -c "$RUNTIME_CONF"
