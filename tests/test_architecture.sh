#!/usr/bin/env bash
# Contrato arquitectónico de edición
# Comprueba que las decisiones de Community y Enterprise permanezcan documentadas.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

titulo "ARCHITECTURE.md — selección y transición de edición"

contiene "documenta la configuración plana" "ODOO_EDITION" "$(cat ARCHITECTURE.md)"
contiene "documenta el tag Community" "19.0-ce-" "$(cat ARCHITECTURE.md)"
contiene "documenta el tag Enterprise" "19.0-ee-" "$(cat ARCHITECTURE.md)"
contiene "documenta la frontera de transición" "frontera operativa" "$(cat ARCHITECTURE.md)"
contiene "documenta el rollback condicionado" "rollback" "$(cat ARCHITECTURE.md)"

resumen
