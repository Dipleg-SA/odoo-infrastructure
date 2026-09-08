#!/usr/bin/env bash
# --- Workspace de VS Code por checkout ---
# Un folder por custom-addons/oca/third-party, uno para 'addons/' (enterprise +
# addons.txt + requirements.txt) y la raíz de infra — generado desde .env, nunca a mano.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

if [ -f .env ]; then . ./.env; fi
: "${COMPOSE_PROJECT_NAME:?declarar COMPOSE_PROJECT_NAME en .env}"

ROOT="$(pwd)"
OUT="$COMPOSE_PROJECT_NAME.code-workspace"
COLOR="1a4d7a"

cat > "$OUT" <<EOF
{
  "folders": [
    { "name": "custom-addons", "path": "$ROOT/addons/custom-addons" },
    { "name": "oca",           "path": "$ROOT/addons/oca" },
    { "name": "third-party",   "path": "$ROOT/addons/third-party" },
    { "name": "addons",        "path": "$ROOT/addons" },
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

# --- Recorte del folder 'addons' ---
# custom-addons/oca/third-party ya son folders propios arriba; sin ocultarlos acá
# VS Code los escanea dos veces y duplica el estado de git de cada módulo. Lo que
# queda visible en 'addons/' es justamente lo que no vive en ningún otro folder:
# enterprise/, addons.txt y requirements.txt (y sus .example).

mkdir -p addons/.vscode
cat > addons/.vscode/settings.json <<EOF
{
  "files.exclude": {
    "custom-addons": true,
    "oca": true,
    "third-party": true
  }
}
EOF

# --- Recorte del root de infra ---
# Todo 'addons/' ya está representado por los cuatro folders de arriba (las tres
# categorías sueltas más 'addons'); sin ocultarlo acá se duplica entero.

mkdir -p .vscode
cat > .vscode/settings.json <<EOF
{
  "files.exclude": {
    "addons": true
  }
}
EOF

ui_ok "generado $OUT, .vscode/settings.json y addons/.vscode/settings.json"
