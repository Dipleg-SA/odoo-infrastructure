#!/usr/bin/env bash
# Rol de solo lectura que el exporter de Postgres de Alloy usa para scrapear.
# Vive con Alloy porque la credencial pertenece al agente de observabilidad.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
contexto_iniciar
SECRETS_VISIBLE="runtime/$ENTORNO/secrets"

# Guarda del stack de observabilidad
# El rol solo se crea cuando el runtime seleccionado declara Alloy y su acceso a Postgres.
if ! contexto_compose config --services 2>/dev/null | grep -qx alloy; then
  ui_bad "Alloy no está en este runtime" "usar ENTORNO=produccion para configurar el stack de observabilidad" >&2
  exit 2
fi

[ -s "$RUNTIME_SECRETS_DIR/postgres_exporter_password" ] || {
  ui_bad "falta $SECRETS_VISIBLE/postgres_exporter_password" \
    "sin él la clave se interpola vacía y el rol queda creado sin password — ¿este stack lleva observabilidad?" >&2
  exit 2
}

ui_plan_start "monitoring-role"
ui_step 1 "Creación (o rotación) del rol de solo lectura que Alloy usa para scrapear Postgres."
printf "DROP ROLE IF EXISTS monitoring;\nCREATE ROLE monitoring LOGIN PASSWORD '%s';\nGRANT pg_monitor TO monitoring;\n" \
  "$(cat "$RUNTIME_SECRETS_DIR/postgres_exporter_password")" \
  | contexto_compose exec -T -u postgres postgres psql -U odoo -d postgres -v ON_ERROR_STOP=1 -q

ui_plan_end
ui_ok "monitoring-role listo"
echo
