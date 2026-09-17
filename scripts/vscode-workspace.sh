#!/usr/bin/env bash
# Workspace operativo de VS Code
# Expone candidatos derivados del entorno sin presentarlos como repositorios editables.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
contexto_iniciar

ROOT="$(pwd)"
OUT="$COMPOSE_PROJECT_NAME.code-workspace"
CANDIDATES_WORKSPACE="$ROOT/runtime/addons/custom/$ENTORNO"
ENTERPRISE_WORKSPACE="$ROOT/runtime/addons/enterprise"
COLOR="1a4d7a"

# Candidatos del entorno
# El workspace requiere una sincronización previa para no abrir un árbol vacío.

if [ ! -d "$CANDIDATES_WORKSPACE" ]; then
  ui_bad "faltan candidatos para $ENTORNO" "ejecutar ENTORNO=$ENTORNO make repo-sync"
  exit 1
fi

# Folder Enterprise opcional
# Solo se agrega cuando la edición seleccionada ya tiene su checkout sincronizado.

enterprise_folder=""
if [ "$ODOO_EDITION" = "enterprise" ] && [ -d "$ENTERPRISE_WORKSPACE" ]; then
  enterprise_folder=",
    { \"name\": \"enterprise — candidato operativo\", \"path\": \"$ENTERPRISE_WORKSPACE\" }"
elif [ "$ODOO_EDITION" = "enterprise" ]; then
  ui_warn "Enterprise no está sincronizado" "el workspace no incluirá runtime/addons/enterprise"
fi

# Workspace generado
# Los folders explícitos evitan mostrar clones bare, builds u otros entornos.

cat > "$OUT" <<EOF
{
  "folders": [
    { "name": "candidatos — $ENTORNO (no editar)", "path": "$CANDIDATES_WORKSPACE" },
    { "name": "infra — operación", "path": "$ROOT" }$enterprise_folder
  ],
  "settings": {
    "window.title": "$COMPOSE_PROJECT_NAME — \${rootName}",
    "terminal.integrated.cwd": "$ROOT",
    "workbench.colorCustomizations": {
      "titleBar.activeBackground": "#$COLOR",
      "titleBar.activeForeground": "#ffffff",
      "titleBar.inactiveBackground": "#$COLOR"
    },
    "files.exclude": {
      "runtime/addons": true,
      ".repos": true,
      "builds": true
    }
  }
}
EOF

ui_ok "generado $OUT"
