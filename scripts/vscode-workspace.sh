#!/usr/bin/env bash
# Workspace de VS Code por checkout
# Un folder por categoría y la raíz de infra, generado desde runtime/compose.env.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
contexto_iniciar

ROOT="$(pwd)"
OUT="$COMPOSE_PROJECT_NAME.code-workspace"
ADDONS_WORKSPACE="$ROOT/runtime/addons"
COLOR="1a4d7a"

cat > "$OUT" <<EOF
{
  "folders": [
    { "name": "addons — $ENTORNO", "path": "$ADDONS_WORKSPACE" },
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

# --- Recorte del folder de addons ---
# Oculta clones bare y builds generados, pero deja visibles catálogo, candidatos y Enterprise.

mkdir -p "$ADDONS_WORKSPACE/.vscode"
cat > "$ADDONS_WORKSPACE/.vscode/settings.json" <<EOF
{
  "files.exclude": {
    ".repos": true,
    "builds": true
  }
}
EOF

# --- Recorte del root de infraestructura ---
# Oculta runtime/addons en la carpeta padre para no mostrar dos veces los mismos archivos.

mkdir -p .vscode
cat > .vscode/settings.json <<EOF
{
  "files.exclude": {
    "runtime/addons": true
  }
}
EOF

ui_ok "generado $OUT, .vscode/settings.json y runtime/addons/.vscode/settings.json"
