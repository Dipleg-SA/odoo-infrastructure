#!/usr/bin/env bash
# Configuración privada por runtime
# Copia los ejemplos de los servicios activos sin pisar valores existentes.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
. scripts/lib/compose.sh
contexto_iniciar

creados=()

# Copia idempotente
# Conserva la ruta relativa del servicio bajo runtime/<entorno>/config/.

copiar_config() {
  local servicio="$1" origen="$2" relativo destino visible
  relativo="${origen#stacks/$servicio/config/}"
  destino="$RUNTIME_CONFIG_DIR/$servicio/${relativo%.example}"
  visible="runtime/$ENTORNO/config/$servicio/${relativo%.example}"
  if [ -e "$destino" ]; then
    ui_skip "skip (ya existe): $visible"
    return
  fi
  mkdir -p "$(dirname "$destino")"
  cp "$origen" "$destino"
  ui_ok "creado: $visible"
  creados+=("$visible")
}

SERVICIOS=$(servicios_activos)
if [ -z "$SERVICIOS" ]; then
  ui_bad "no se pudo leer los servicios de la composición" "revisar ENTORNO y runtime/$ENTORNO/compose.env" >&2
  exit 1
fi

# Línea mayor para webhooks
# Se comparte con el receptor para aceptar solo ramas de esta imagen Odoo.
ODOO_VERSION="$(contexto_odoo_version | head -1)"
if [ -z "$ODOO_VERSION" ]; then
  ui_bad "no se pudo leer la línea de Odoo" "revisar FROM odoo: en stacks/odoo/image/Dockerfile" >&2
  exit 1
fi
mkdir -p runtime/control/secrets runtime/control/state
printf '%s\n' "$ODOO_VERSION" > runtime/control/state/odoo-version

ui_plan_start "config-init"
ui_step 1 "Bootstrapeo de configs para entorno $ENTORNO. Si alguno existe, se omite la copia."

# Servicios activos
# Copia sus plantillas y archivos versionados, excepto archivos ya representados por .example.

for svc in $SERVICIOS; do
  [ -d "stacks/$svc/config" ] || continue
  while IFS= read -r ejemplo; do
    copiar_config "$svc" "$ejemplo"
  done < <(find "stacks/$svc/config" -name '*.example' | sort)
  while IFS= read -r archivo; do
    [ -f "$archivo.example" ] && continue
    copiar_config "$svc" "$archivo"
  done < <(find "stacks/$svc/config" -type f ! -name '*.example' ! -name '.gitkeep' | sort)
done

ui_plan_end
if [ "${#creados[@]}" -gt 0 ]; then
  ui_ok "Bootstrapeados ${#creados[@]} archivos. Completá los que pidan un valor real."
else
  ui_skip "Nada para crear: ya estaba todo bootstrapeado."
fi
echo
