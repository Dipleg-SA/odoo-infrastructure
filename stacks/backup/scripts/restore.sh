#!/usr/bin/env bash
# Restore desde un snapshot de restic: la otra dirección de la misma herramienta.
# Se invoca a mano, primero para el filestore y después para la base.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh

# Contexto del runtime
# Compose y el estado restaurado deben pertenecer al entorno seleccionado; no hay fallback global.
[ -n "${ENTORNO:-}" ] || { ui_bad "falta ENTORNO" "usar ENTORNO=staging o ENTORNO=produccion" >&2; exit 2; }
. scripts/lib/contexto.sh
contexto_iniciar
META_DIR="$RUNTIME_STATE_DIR/meta"
compose() { contexto_compose "$@"; }

SNAPSHOT="${1:-latest}"
DUMP_PATH=/dumps/odoo.sql

# --- Guarda ---
# Odoo debe estar detenido y Postgres disponible antes de restaurar.

if [ -n "$(compose ps -q odoo 2>/dev/null)" ]; then
  ui_bad "odoo está corriendo" "restaurar con la aplicación viva mezcla datos — make odoo-down" >&2
  exit 2
fi
if [ -z "$(compose ps -q postgres 2>/dev/null)" ]; then
  ui_bad "postgres no está corriendo" "el restore de la base necesita el motor arriba — make postgres-up" >&2
  exit 2
fi

ui_plan_start "restore desde el snapshot '$SNAPSHOT'"
ui_step 1 "Restore del filestore y la base desde el snapshot '$SNAPSHOT'."

# --- Cómo se invoca el contenedor ---
# Root y un entrypoint explícito son puntuales: el servicio recurrente sigue no-root.

en_backup() {
  compose run --rm --user 0:0 --entrypoint "$1" -T backup "${@:2}"
}

# --- Filestore ---
# Restore del filestore antes de cargar la base.

ui_run "restore del filestore" en_backup restic restore "$SNAPSHOT" --target / --include /data/odoo

# Metadata de procedencia
# El restore debe usar la metadata del snapshot, no una copia local que puede pertenecer a otro estado.
ui_run "restore de metadata" en_backup restic restore "$SNAPSHOT" --target / --include /data/meta

# 100:101 son los uid/gid de Odoo: restaurado como root, el filestore le queda
# ilegible a la aplicación si no se le devuelve el owner.
ui_run "owner del filestore" en_backup chown -R 100:101 /data/odoo

# --- Dump ---
# Se restaura al volumen compartido que luego lee Postgres.

ui_run "restore del dump" en_backup restic restore "$SNAPSHOT" --target / --include /data/dump

# --- Base ---
# La base se recrea antes de cargar el dump lógico para fallar al comienzo.

ui_run "recrear la base" compose exec -T postgres sh -c \
  'dropdb -U odoo --if-exists odoo && createdb -U odoo -O odoo odoo'

ui_run "cargar el dump" compose exec -T postgres sh -c \
  "psql -U odoo -d odoo -v ON_ERROR_STOP=1 -f $DUMP_PATH"

# Procedencia de imagen
# El restore debe dejar Actual y Anterior alineadas con el snapshot recuperado.
if [ -f "$META_DIR/images.json" ]; then
  scripts/image-state.sh restore-meta "$META_DIR/images.json"
else
  ui_bad "falta procedencia de imágenes" "el snapshot no contiene state/meta/images.json"
  exit 1
fi

ui_plan_end
ui_ok "restore listo — levantá la aplicación con make odoo-up para reaplicar la configuración de reportes"
echo
