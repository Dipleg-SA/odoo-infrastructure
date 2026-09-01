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

# --- Color estable por checkout ---
# Hash del nombre a un índice de paleta fija: mismo checkout, mismo color
# siempre; checkouts distintos, colores distintos sin elegir a mano.

PALETTE=(2d5f3f 5f2d4f 2d4f5f 5f4f2d 4f2d5f 2d5f2d)
HASH=$(cksum <<<"$COMPOSE_PROJECT_NAME" | cut -d' ' -f1)
COLOR="${PALETTE[$((HASH % ${#PALETTE[@]}))]}"

cat > "$OUT" <<EOF
{
  "folders": [
    { "name": "🏢 enterprise",    "path": "$ROOT/addons/enterprise" },
    { "name": "📦 custom-addons", "path": "$ROOT/addons/custom-addons" },
    { "name": "🔧 oca",           "path": "$ROOT/addons/oca" },
    { "name": "🌐 third-party",   "path": "$ROOT/addons/third-party" },
    { "name": "⚙️ infra — solo terminal, NO editar", "path": "$ROOT" }
  ],
  "settings": {
    "window.title": "$COMPOSE_PROJECT_NAME — \${rootName}",
    "workbench.colorCustomizations": {
      "titleBar.activeBackground": "#$COLOR",
      "titleBar.activeForeground": "#ffffff",
      "titleBar.inactiveBackground": "#$COLOR"
    }
  }
}
EOF

ui_ok "generado $OUT"
