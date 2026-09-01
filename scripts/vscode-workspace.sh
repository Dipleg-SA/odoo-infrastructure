#!/usr/bin/env bash
# --- Workspace de VS Code por checkout ---
# Un folder fijo por tipo de addon (enterprise/custom-addons/oca/third-party)
# más la raíz de infra, generado desde .env — nunca a mano.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

if [ -f .env ]; then . ./.env; fi
: "${COMPOSE_PROJECT_NAME:?declarar COMPOSE_PROJECT_NAME en .env}"

ROOT="$(pwd)"
OUT="dev.code-workspace"
COLOR="1a4d7a"

cat > "$OUT" <<EOF
{
  "folders": [
    { "name": "enterprise",    "path": "$ROOT/addons/enterprise" },
    { "name": "custom-addons", "path": "$ROOT/addons/custom-addons" },
    { "name": "oca",           "path": "$ROOT/addons/oca" },
    { "name": "third-party",   "path": "$ROOT/addons/third-party" },
    { "name": "infra — solo terminal, NO editar", "path": "$ROOT" }
  ],
  "settings": {
    "window.title": "$COMPOSE_PROJECT_NAME — \${rootName}",
    "terminal.integrated.cwd": "$ROOT",
    "workbench.colorCustomizations": {
      "titleBar.activeBackground": "#$COLOR",
      "titleBar.activeForeground": "#ffffff",
      "titleBar.inactiveBackground": "#$COLOR"
    }
  }
}
EOF

# --- Recorte del root de infra ---
# addons/ ya está representado por los cuatro folders de arriba; sin ocultarlo
# acá VS Code lo escanea dos veces y duplica el estado de git de cada módulo.

mkdir -p .vscode
cat > .vscode/settings.json <<EOF
{
  "files.exclude": {
    "addons": true
  }
}
EOF

ui_ok "generado $OUT y .vscode/settings.json"
