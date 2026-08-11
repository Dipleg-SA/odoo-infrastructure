#!/usr/bin/env bash
# Chequeo de integridad ir_attachment <-> filestore. Paso obligatorio
# después de un restore: la base y los archivos se respaldan por caminos distintos,
# así que un restore desalineado deja adjuntos rotos sin que nada más lo note.
set -euo pipefail

cd "$(dirname "$0")/.."

DB="${1:-odoo}"

# --- Adjuntos que la base referencia ---
# store_fname es NULL para los que Odoo guarda dentro de la propia base.

docker compose exec -T -u postgres postgres \
  psql -U odoo -d "$DB" -tAc \
  "select store_fname from ir_attachment where store_fname is not null and store_fname <> '';" \
| docker compose exec -T backup sh -c '
  db="$1"; total=0; faltan=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    total=$((total+1))
    [ -f "/data/odoo/filestore/$db/$f" ] || { echo "FALTA: $f"; faltan=$((faltan+1)); }
  done
  echo "referenciados: $total | faltantes: $faltan"
  [ "$faltan" -eq 0 ]
' _ "$DB"
