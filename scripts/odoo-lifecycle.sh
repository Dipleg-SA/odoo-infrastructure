#!/usr/bin/env bash
# Ciclo de vida de Odoo
# Valida código e imagen y recrea el contenedor bajo el lock del entorno.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
. scripts/lib/candidate-lock.sh
contexto_iniciar

# Exclusión compartida
# Webhook, sync, build, lifecycle y módulos no pueden cambiar el árbol a la vez.
if [ "${CANDIDATE_LOCK_HELD:-0}" != 1 ]; then
  candidate_lock_run "$ENTORNO" -- env CANDIDATE_LOCK_HELD=1 "$0" "$@"
  exit $?
fi

# Acción explícita
# up y restart comparten recreación porque un bind reemplazado puede conservar el inode anterior.
case "${1:-}" in
  up|restart|stack-up) accion="$1" ;;
  *) printf 'Uso: ENTORNO=<entorno> %s up|restart|stack-up\n' "$(basename "$0")" >&2; exit 2 ;;
esac

scripts/addons-runtime.sh preflight
if [ "$accion" = stack-up ]; then
  ui_run "up" contexto_compose up -d
fi
ui_run "odoo-$accion" contexto_compose up -d --force-recreate odoo
