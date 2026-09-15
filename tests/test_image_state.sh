#!/usr/bin/env bash
# Contrato del estado de imágenes
# Verifica ranuras, procedencia obligatoria y escritura sin truncar el JSON.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
TMP=$(mktemp -d)
CREADO=0
trap 'rm -rf "$TMP"; [ "$CREADO" -eq 0 ] || rm -f runtime/desarrollo/compose.env; rm -f runtime/desarrollo/state/images.json' EXIT
if [ ! -f runtime/desarrollo/compose.env ]; then cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env; CREADO=1; fi
rm -f runtime/desarrollo/state/images.json
export ENTORNO=desarrollo
SCRIPT=scripts/image-state.sh

igual "estado inicial declara tres ranuras" '{"Actual": null, "Anterior": null, "Nueva": null, "validation": null}' "$("$SCRIPT" show | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')"
PAYLOAD='{"tag":"local/odoo:19.0-desarrollo-utc-hash","digest":"sha256:abc","odoo_version":"19.0","base_image":"odoo:19.0-20260810","infra_commit":"infra","enterprise_tag":"19.0-ee-2026-09-14","enterprise_commit":"ee","addons":{"ventas":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"built_at":"20260914T120000Z"}'
igual "write-new publica Nueva" 'local/odoo:19.0-desarrollo-utc-hash' "$("$SCRIPT" write-new "$PAYLOAD" >/dev/null; "$SCRIPT" get Nueva | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
sale_con "rechaza procedencia incompleta" 1 "$SCRIPT" write-new '{"tag":"incompleto"}'
sale_con "valida el estado" 0 "$SCRIPT" validate
resumen
