#!/usr/bin/env bash
# Chequeo de integridad ir_attachment <-> filestore. Paso obligatorio
# después de un restore: la base y los archivos se respaldan por caminos distintos,
# así que un restore desalineado deja adjuntos rotos sin que nada más lo note.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

DB="${1:-odoo}"

ui_plan_start "integrity-check"
ui_step 1 "Verificación de que cada adjunto referenciado en ir_attachment exista en el filestore de '$DB'."

# --- Adjuntos que la base referencia ---
# store_fname es NULL para los que Odoo guarda dentro de la propia base.
#
# El recorrido va por el contenedor de odoo, no por el de backup: ese es exclusivo
# de producción, y este chequeo es justo el que quiere un simulacro en staging.

ec=0
docker compose exec -T -u postgres postgres \
  psql -U odoo -d "$DB" -tAc \
  "select store_fname from ir_attachment where store_fname is not null and store_fname <> '';" \
| docker compose exec -T odoo sh -c '
  db="$1"; total=0; faltan=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    total=$((total+1))
    [ -f "/var/lib/odoo/filestore/$db/$f" ] || { echo "FALTA: $f"; faltan=$((faltan+1)); }
  done
  echo "referenciados: $total | faltantes: $faltan"
  [ "$faltan" -eq 0 ]
' _ "$DB" || ec=$?

ui_plan_end
if [ "$ec" -eq 0 ]; then ui_ok "integrity-check listo — sin adjuntos faltantes"
else ui_bad "integrity-check falló" "revisá la salida de arriba — puede ser adjuntos faltantes o que postgres/odoo no respondieran"; fi
echo
exit "$ec"
