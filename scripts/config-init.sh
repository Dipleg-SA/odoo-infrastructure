#!/usr/bin/env bash
# Bootstrapea los config reales de cada stack activo desde su .example: cp
# idempotente, nunca pisa un archivo que ya exista.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh
. scripts/lib/compose.sh

ENTORNO=$(sed -n 's|^COMPOSE_FILE=envs/\(.*\)\.yaml$|\1|p' .env 2>/dev/null)

ui_plan_start "config-init"
ui_step 1 "Bootstrapeo de configs${ENTORNO:+ para entorno $ENTORNO}. Si alguno existe, se omite la copia."

creados=()

# --- Helper ---
# Escribe solo si el destino no existe; el nombre real sale de sacarle el .example.

nuevo() {
  local origen="$1" destino="${1%.example}"
  if [ -e "$destino" ]; then
    ui_skip "skip (ya existe): $destino"
    return
  fi
  cp "$origen" "$destino"
  ui_ok "creado: $destino"
  creados+=("$destino")
}

SERVICIOS=$(servicios_activos)
if [ -z "$SERVICIOS" ]; then
  ui_bad "no se pudo leer los servicios de la composición" "revisar COMPOSE_FILE en .env" >&2
  exit 1
fi

# --- Config de cada stack activo ---
# Un stack ausente de la composición no bootstrapea archivos inertes: ningún
# verify.sh de un stack omitido va a pedir que se completen.

for svc in $SERVICIOS; do
  [ -d "stacks/$svc/config" ] || continue
  while IFS= read -r ejemplo; do
    nuevo "$ejemplo"
  done < <(find "stacks/$svc/config" -name '*.example' | sort)
done

# --- Addons ---
# No vive bajo stacks/<nombre>/config/ —es del entrypoint, no de un stack— pero
# solo tiene sentido si Odoo está en la composición.

if printf '%s\n' "$SERVICIOS" | grep -qx odoo; then
  nuevo addons/addons.txt.example
  nuevo addons/requirements.txt.example
fi

echo
ui_step 2 "Finalizado."
if [ "${#creados[@]}" -gt 0 ]; then
  ui_ok "Bootstrapeados ${#creados[@]} archivos. Completá los que pidan un valor real."
else
  ui_skip "Nada para crear: ya estaba todo bootstrapeado."
fi
echo
