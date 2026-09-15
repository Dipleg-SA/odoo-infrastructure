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

igual "estado inicial declara ranuras y bloqueo" '{"Actual": null, "Anterior": null, "Nueva": null, "module_operations": [], "rollback_blocked": false, "validation": null}' "$("$SCRIPT" show | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')"
PAYLOAD='{"tag":"local/odoo:19.0-desarrollo-utc-hash","digest":"sha256:abc","odoo_version":"19.0","base_image":"odoo:19.0-20260810","infra_commit":"infra","enterprise_tag":"19.0-ee-2026-09-14","enterprise_commit":"ee","addons":{"ventas":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"built_at":"20260914T120000Z"}'
igual "write-new publica Nueva" 'local/odoo:19.0-desarrollo-utc-hash' "$("$SCRIPT" write-new "$PAYLOAD" >/dev/null; "$SCRIPT" get Nueva | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
sale_con "rechaza procedencia incompleta" 1 "$SCRIPT" write-new '{"tag":"incompleto"}'
BAD_PAYLOAD=$(python3 -c 'import json,sys; data=json.loads(sys.argv[1]); data["tag"]="local/odoo:19.0-desarrollo-$(touch /tmp/image-state-test-pwned)"; print(json.dumps(data))' "$PAYLOAD")
sale_con "rechaza una referencia de imagen ejecutable" 1 "$SCRIPT" write-new "$BAD_PAYLOAD"
sale_con "valida el estado" 0 "$SCRIPT" validate
"$SCRIPT" apply >/dev/null
igual "promueve Nueva a Actual" 'local/odoo:19.0-desarrollo-utc-hash' "$("$SCRIPT" get Actual | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
PAYLOAD2="${PAYLOAD/utc-hash/utc-hash-2}"
"$SCRIPT" write-new "$PAYLOAD2" >/dev/null
"$SCRIPT" apply >/dev/null
igual "conserva Actual previa en Anterior" 'local/odoo:19.0-desarrollo-utc-hash' "$("$SCRIPT" get Anterior | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
"$SCRIPT" validate-image "smoke staging" >/dev/null
contiene "registra la validación" 'smoke staging' "$("$SCRIPT" get validation)"
"$SCRIPT" rollback "prueba" >/dev/null
igual "reactiva Anterior" 'local/odoo:19.0-desarrollo-utc-hash' "$("$SCRIPT" get Actual | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
"$SCRIPT" write-new "$PAYLOAD2" >/dev/null
"$SCRIPT" apply >/dev/null
"$SCRIPT" invalidate-rollback "update:ventas" >/dev/null
sale_con "bloquea rollback tras módulos" 1 "$SCRIPT" rollback

# Estado manipulado
# Una fotografía alterada no puede llegar a compose.env como código ejecutable.
MALICIOUS_MARKER="$TMP/image-state-test-pwned"
MALICIOUS_TAG="local/odoo:19.0-desarrollo-\$(touch $MALICIOUS_MARKER)"
python3 - "runtime/desarrollo/state/images.json" "$MALICIOUS_TAG" <<'PY'
import json, sys
path, tag = sys.argv[1:]
data = json.loads(open(path, encoding="utf-8").read())
data["Nueva"] = dict(data["Actual"])
data["Nueva"]["tag"] = tag
open(path, "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
ENV_ANTES=$(cat runtime/desarrollo/compose.env)
sale_con "no promueve una etiqueta manipulada" 1 "$SCRIPT" apply
igual "no escribe compose.env ni ejecuta la etiqueta" "$ENV_ANTES" "$(cat runtime/desarrollo/compose.env)"
igual "la etiqueta no ejecuta comandos del host" "0" "$([ ! -e "$MALICIOUS_MARKER" ]; echo $?)"
resumen
