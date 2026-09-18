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
  # Procedencia de la imagen seleccionada
  # Para retirar Enterprise se consulta el inventario del build que usa ODOO_IMAGE.
  BUILD_ROOT="$(cd "$RUNTIME_DIR/../addons/builds/$ENTORNO" 2>/dev/null && pwd -P || true)"
  if ! python3 - "$ODOO_IMAGE" "$modulos" "$BUILD_ROOT" <<'PY'
import json, sys
from pathlib import Path

selected_tag, installed_raw, build_root = sys.argv[1:]
installed = set(filter(None, installed_raw.split(',')))
metadata = None
if build_root:
    for path in sorted(Path(build_root).glob('*/image.json')):
        try:
            candidate = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            continue
        if candidate.get('tag') == selected_tag:
            metadata = candidate
            break
if metadata is None or metadata.get('edition') != 'enterprise':
    raise SystemExit(0)
enterprise = metadata.get('enterprise_modules')
if not isinstance(enterprise, list):
    raise SystemExit(1)
enterprise = set(enterprise)
if installed & enterprise:
    print('módulos Enterprise instalados: ' + ', '.join(sorted(installed & enterprise)), file=sys.stderr)
    raise SystemExit(1)
PY
  then
    printf 'la base no es compatible con Community\n' >&2
    exit 1
  fi
  printf 'base compatible con Community\n'
fi

exit 0
