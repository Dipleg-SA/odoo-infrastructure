#!/usr/bin/env bash
# Rol de solo lectura que el exporter de Postgres de Alloy usa para scrapear.
#
# Vive con alloy y no con postgres aunque haga psql contra postgres: es SU
# credencial, y sin este stack el rol no existe para nadie. Repetible: el DROP
# lo hace idempotente, y sirve tanto para crearlo como para rotar la clave.
#
# pg_monitor y no superuser: el agente que tiene el socket de Docker y los logs
# no porta la credencial de la aplicación.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh

[ -s secrets/postgres_exporter_password ] || {
  ui_bad "falta secrets/postgres_exporter_password" \
    "sin él la clave se interpola vacía y el rol queda creado sin password — ¿este stack lleva observabilidad?" >&2
  exit 2
}

ui_start "monitoring-role"
printf "DROP ROLE IF EXISTS monitoring;\nCREATE ROLE monitoring LOGIN PASSWORD '%s';\nGRANT pg_monitor TO monitoring;\n" \
  "$(cat secrets/postgres_exporter_password)" \
  | docker compose exec -T -u postgres postgres psql -U odoo -d postgres -v ON_ERROR_STOP=1 -q
ui_ok "monitoring-role listo"
