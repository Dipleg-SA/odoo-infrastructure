#!/usr/bin/env bash
# Ejecuta operaciones de módulos mediante la API ORM de Odoo.
#
# El código de los addons debe seguir montado cuando se ejecuta este script. La
# desinstalación ocurre antes de quitar un módulo del manifiesto o del worktree.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
. scripts/lib/candidate-lock.sh
contexto_iniciar

# Exclusión compartida
# La publicación y las operaciones funcionales no pueden observar árboles distintos.
if [ "${CANDIDATE_LOCK_HELD:-0}" != 1 ]; then
  candidate_lock_run "$ENTORNO" -- env CANDIDATE_LOCK_HELD=1 "$0" "$@"
  exit $?
fi

ACCION="${1:-}"
MODULOS="${MODULES:-}"

case "$ACCION" in
  install|update|uninstall) ;;
  *)
    ui_bad "operación de módulos inválida" "usar install, update o uninstall"
    exit 2
    ;;
esac

if [ -z "$MODULOS" ]; then
  ui_bad "faltan módulos" "usar MODULES=nombre_del_modulo[,otro_modulo]"
  exit 2
fi

case ",$MODULOS," in
  *,\ *,*|*,,*|,*[!a-zA-Z0-9_,]*,*)
    ui_bad "MODULES inválido" "usar nombres técnicos separados por comas, sin espacios"
    exit 2
    ;;
esac

if [ "$ACCION" = uninstall ] && [ "$MODULOS" = all ]; then
  ui_bad "desinstalación masiva bloqueada" "addons-uninstall requiere módulos explícitos"
  exit 2
fi

# Imagen Odoo seleccionada
# Las operaciones ORM usan el mismo selector local que consume Compose.
if ! make require-odoo-image >/dev/null 2>&1; then
  ui_bad "imagen Odoo no disponible" "ejecutá ENTORNO=$ENTORNO make build antes de operar módulos"
  exit 2
fi
scripts/addons-runtime.sh preflight

# Identidad de la operación
# El proyecto y el entorno evitan colisiones entre checkouts y composiciones concurrentes.
PROYECTO="${COMPOSE_PROJECT_NAME:-}"
[ -n "$PROYECTO" ] || {
  ui_bad "falta COMPOSE_PROJECT_NAME" "revisar runtime/$ENTORNO/compose.env"
  exit 2
}
IDENTIDAD_OPERACION="${PROYECTO}-${ENTORNO}"
ONEOFF_NAME="${IDENTIDAD_OPERACION}-odoo-oneoff"

python_operacion() {
  contexto_compose run --rm --name "$ONEOFF_NAME" \
    -e "ODOO_OPERATION=$ACCION" \
    -e "ODOO_MODULES=$MODULOS" \
    -e "ODOO_PHASE=$1" \
    -e "CONFIRM=${CONFIRM:-}" \
    odoo shell --no-http <<'PY'
import os
import sys

Modules = env['ir.module.module'].sudo()
operation = os.environ['ODOO_OPERATION']
phase = os.environ['ODOO_PHASE']
requested = [name.strip() for name in os.environ['ODOO_MODULES'].split(',') if name.strip()]

if operation != 'uninstall':
    Modules.update_list()

if requested == ['all']:
    states = {
        'install': [('state', '=', 'uninstalled')],
        'update': [('state', 'in', ('installed', 'to upgrade'))],
    }
    selected = Modules.search(states[operation])
else:
    selected = Modules.search([('name', 'in', requested)])

found = set(selected.mapped('name'))
missing = sorted(set(requested) - found) if requested != ['all'] else []
if missing:
    print('Módulos no encontrados: %s' % ', '.join(missing))
    sys.exit(2)

valid_states = {
    'install': {'uninstalled'},
    'update': {'installed', 'to upgrade'},
    'uninstall': {'installed', 'to upgrade'},
}
invalid = selected.filtered(lambda module: module.state not in valid_states[operation])
if invalid:
    print('Módulos fuera de estado para %s: %s' % (
        operation,
        ', '.join('%s=%s' % (module.name, module.state) for module in invalid),
    ))
    sys.exit(2)

if not selected:
    print('No hay módulos para %s.' % operation)
    sys.exit(2)

if operation == 'uninstall':
    impacted = selected | selected.downstream_dependencies()
    print('Módulos solicitados: %s' % ', '.join(selected.mapped('name')))
    print('Módulos afectados: %s' % ', '.join(impacted.mapped('name')))
    if phase == 'preflight':
        sys.exit(0)
    if os.environ.get('CONFIRM') != 'desinstalar':
        print("Falta CONFIRM=desinstalar para ejecutar la desinstalación.")
        sys.exit(2)
    selected.button_immediate_uninstall()
elif operation == 'install':
    selected.button_immediate_install()
elif operation == 'update':
    selected.button_immediate_upgrade()
PY
}

ODOO_DETENIDO=0

levantar_odoo() {
  local estado_original="$1" estado_up=0 estado_config=0

  if [ "$ODOO_DETENIDO" -ne 1 ]; then
    return "$estado_original"
  fi

  if ui_run "levantar Odoo" scripts/odoo-lifecycle.sh up; then
    estado_up=0
  else
    estado_up=$?
  fi
  ODOO_DETENIDO=0

  if [ "$estado_up" -eq 0 ]; then
    if ui_run "validar configuración de reportes" make odoo-report-config; then
      estado_config=0
    else
      estado_config=$?
    fi
  fi

  if [ "$estado_original" -ne 0 ]; then
    return "$estado_original"
  fi
  [ "$estado_up" -ne 0 ] && return "$estado_up"
  return "$estado_config"
}

limpiar() {
  local estado=$?
  local estado_restaurar=0
  trap - EXIT
  set +e
  levantar_odoo "$estado"
  estado_restaurar=$?
  exit "$estado_restaurar"
}

trap limpiar EXIT

ui_start "addons-$ACCION $MODULOS"
ODOO_DETENIDO=1
if ui_run "detener Odoo" contexto_compose stop odoo; then
  :
else
  estado_detener=$?
  exit "$estado_detener"
fi

if [ "$ACCION" = uninstall ]; then
  ui_step 1 "Previsualizar módulos afectados antes de desinstalar."
  python_operacion preflight
  if [ "${CONFIRM:-}" != desinstalar ]; then
    ui_confirm desinstalar
  fi
fi

if [ "$ACCION" = uninstall ]; then
  ui_step 2 "Ejecutar la desinstalación mediante la API ORM de Odoo."
else
  ui_step 1 "Ejecutar la operación mediante la API ORM de Odoo."
fi

estado_operacion=0
python_operacion apply || estado_operacion=$?
exit "$estado_operacion"
