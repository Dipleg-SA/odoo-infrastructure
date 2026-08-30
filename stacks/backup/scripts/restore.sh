#!/usr/bin/env bash
# Restore desde un snapshot de restic: la otra dirección de la misma herramienta.
# Se invoca a mano — nunca por timer, nunca al arrancar.
#
# El orden importa y no es simétrico al del backup: primero el filestore, después
# la base. Un filestore más nuevo que la base deja archivos huérfanos, que son
# inofensivos; uno más viejo deja filas apuntando a archivos que no existen, que
# es destructivo y silencioso.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh

if [ -f .env ]; then set -a; . ./.env; set +a; fi

SNAPSHOT="${1:-latest}"
DUMP_PATH=/dumps/odoo.sql

# --- Guarda ---
# Restaurar sobre una base con Odoo escribiendo deja el cluster a medias: las
# conexiones vivas bloquean el DROP y lo que sí entra queda mezclado.

if [ -n "$(docker compose ps -q odoo 2>/dev/null)" ]; then
  ui_bad "odoo está corriendo" "restaurar con la aplicación viva mezcla datos — make odoo-down" >&2
  exit 2
fi
if [ -z "$(docker compose ps -q postgres 2>/dev/null)" ]; then
  ui_bad "postgres no está corriendo" "el restore de la base necesita el motor arriba — make postgres-up" >&2
  exit 2
fi

ui_plan_start "restore desde el snapshot '$SNAPSHOT'"
ui_step 1 "Restore del filestore y la base desde el snapshot '$SNAPSHOT'."

# --- Cómo se invoca el contenedor ---
# --user 0:0 en la invocación y no en el compose: así la operación recurrente —el
# backup diario— sigue corriendo no-root. Root hace falta por dos motivos: un
# volumen recién creado nace root:root y ningún no-root puede crear ahí el primer
# directorio, y solo root le devuelve a cada archivo el owner del snapshot.
#
# --entrypoint es obligatorio: el servicio declara `entrypoint: ["sleep"]` para
# poder colgarle un healthcheck, así que sin esto `run backup restic ...`
# ejecutaría `sleep restic ...` y devolvería 0 sin restaurar nada.

en_backup() {
  docker compose run --rm --user 0:0 --entrypoint "$1" -T backup "${@:2}"
}

# --- Filestore ---

ui_run "restore del filestore" en_backup restic restore "$SNAPSHOT" --target / --include /data/odoo

# 100:101 son los uid/gid de Odoo: restaurado como root, el filestore le queda
# ilegible a la aplicación si no se le devuelve el owner.
ui_run "owner del filestore" en_backup chown -R 100:101 /data/odoo

# --- Dump ---
# Al volumen que postgres monta rw, para poder alimentárselo por psql.

ui_run "restore del dump" en_backup restic restore "$SNAPSHOT" --target / --include /data/dump

# --- Base ---
# La base se recrea entera: el dump es lógico y no aplica sobre un esquema que ya
# existe sin chocar con cada objeto. dropdb/createdb y no --clean para que el
# fallo, si lo hay, sea al principio y no a mitad de la carga.

ui_run "recrear la base" docker compose exec -T postgres sh -c \
  'dropdb -U odoo --if-exists odoo && createdb -U odoo -O odoo odoo'

ui_run "cargar el dump" docker compose exec -T postgres sh -c \
  "psql -U odoo -d odoo -v ON_ERROR_STOP=1 -f $DUMP_PATH"

ui_plan_end
ui_ok "restore listo — levantá la aplicación con make odoo-up"
echo
