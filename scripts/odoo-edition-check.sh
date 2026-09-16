#!/usr/bin/env bash
# Preflight de cambio de edición
# Consulta los módulos instalados sin modificar la base ni ejecutar operaciones funcionales.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/contexto.sh
contexto_iniciar || exit $?

DESTINO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --destino)
      [ "$#" -ge 2 ] || { printf 'falta el valor de --destino\n' >&2; exit 2; }
      DESTINO="$2"
      shift 2
      ;;
    *)
      printf 'uso: ENTORNO=<entorno> %s --destino <community|enterprise>\n' "$(basename "$0")" >&2
      exit 2
      ;;
  esac
done

case "$DESTINO" in
  community|enterprise) ;;
  *)
    printf 'destino inválido: usar community o enterprise\n' >&2
    exit 2
    ;;
esac

# Consulta ORM de solo lectura
# El código corre en un one-off y solo lee ir.module.module mediante el entorno de Odoo.
salida=""
if ! salida=$(contexto_compose run --rm --name odoo-edition-check odoo shell --no-http <<'PY'
import sys

modules = env['ir.module.module'].sudo().search([('state', '=', 'installed')])
names = sorted(modules.mapped('name'))
print('ODOO_EDITION_CHECK_MODULES=' + ','.join(names))
sys.exit(0)
PY
); then
  printf 'no se pudo consultar la base mediante Odoo ORM\n' >&2
  exit 2
fi

# Resultado del preflight
# Informa todos los módulos instalados y bloquea Community solo con evidencia Enterprise.
if ! printf '%s\n' "$salida" | grep -q '^ODOO_EDITION_CHECK_MODULES='; then
  printf 'la consulta ORM no devolvió el inventario de módulos\n' >&2
  exit 2
fi
modulos=$(printf '%s\n' "$salida" | sed -n 's/^ODOO_EDITION_CHECK_MODULES=//p' | tail -1)

printf 'edición destino: %s\n' "$DESTINO"
printf 'módulos instalados: %s\n' "${modulos:-ninguno}"

if [ "$DESTINO" = community ]; then
  # Inventario Enterprise histórico
  # Para retirar Enterprise se exige un inventario explícito de la imagen activa.
  actual=$(scripts/image-state.sh get Actual 2>/dev/null || printf 'null')
  if ! python3 - "$actual" "$modulos" "$RUNTIME_STATE_DIR/images.json" <<'PY'
import json, sys

actual = json.loads(sys.argv[1])
installed = set(filter(None, sys.argv[2].split(',')))
raw_state = json.load(open(sys.argv[3], encoding='utf-8'))
if actual is None or actual.get('edition') != 'enterprise':
    raise SystemExit(0)
raw_actual = raw_state.get('Actual')
if not isinstance(raw_actual, dict) or not isinstance(raw_actual.get('enterprise_modules'), list):
    raise SystemExit(1)
enterprise = set(raw_actual['enterprise_modules'])
if installed & enterprise:
    print('módulos Enterprise instalados: ' + ', '.join(sorted(installed & enterprise)), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    printf 'la base no es compatible con Community\n' >&2
    exit 1
  fi
fi

exit 0
