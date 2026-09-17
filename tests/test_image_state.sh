#!/usr/bin/env bash
# Contrato del estado de imágenes
# Verifica ranuras, procedencia obligatoria y escritura sin truncar el JSON.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
TMP=$(mktemp -d)
REPO_ROOT="$PWD"
ROOT="$TMP/repo"
mkdir -p "$ROOT/runtime/desarrollo"
cp -R "$REPO_ROOT/scripts" "$ROOT/"
cp "$REPO_ROOT/runtime/desarrollo/compose.env.example" "$ROOT/runtime/desarrollo/compose.env"
printf 'services: {}\n' > "$ROOT/runtime/desarrollo/compose.yaml"
tar -cf "$TMP/runtime-before.tar" -C "$REPO_ROOT" runtime
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
export ENTORNO=desarrollo
SCRIPT=scripts/image-state.sh

"$SCRIPT" show >/dev/null
cat > "$TMP/without-actual.json" <<'EOF'
{"Actual": null, "Anterior": null, "Nueva": null, "module_operations": [], "rollback_blocked": false, "validation": null}
EOF
ESTADO_ANTES=$(cat runtime/desarrollo/state/images.json)
sale_con "restore rechaza un snapshot sin Actual" 1 "$SCRIPT" restore-meta "$TMP/without-actual.json"
igual "restore no muta el estado si falta Actual" "$ESTADO_ANTES" "$(cat runtime/desarrollo/state/images.json)"

igual "estado inicial declara ranuras y bloqueo" '{"Actual": null, "Anterior": null, "Nueva": null, "module_operations": [], "rollback_blocked": false, "validation": null}' "$("$SCRIPT" show | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')"
PAYLOAD='{"tag":"local/odoo:19.0-desarrollo-utc-hash","digest":"sha256:abc","odoo_version":"19.0","base_image":"odoo:19.0-20260810","infra_commit":"infra","edition":"community","edition_tag":"19.0-ce-2026-09-16","enterprise_tag":null,"enterprise_commit":null,"enterprise_modules":[],"addons":{"ventas":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"built_at":"20260914T120000Z"}'
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
contiene "promoción conserva edición Community" '"edition": "community"' "$($SCRIPT get Actual)"
contiene "promoción conserva tag de edición" '"edition_tag": "19.0-ce-2026-09-16"' "$($SCRIPT get Actual)"

# Ranuras cruzadas e inferencia histórica
# Una fotografía Enterprise no se puede activar en un runtime Community.
PAYLOAD_EE='{"tag":"local/odoo:19.0-desarrollo-ee-hash","digest":"sha256:ee","odoo_version":"19.0","base_image":"odoo:19.0-20260810","infra_commit":"infra","edition":"enterprise","edition_tag":"19.0-ee-2026-09-14","enterprise_tag":"19.0-ee-2026-09-14","enterprise_commit":"ee","enterprise_modules":["ventas"],"addons":{"ventas":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"built_at":"20260914T120000Z"}'
python3 - "runtime/desarrollo/state/images.json" "$PAYLOAD_EE" <<'PY'
import json, sys
path, payload = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
data["Nueva"] = json.loads(payload)
open(path, "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
sale_con "bloquea Nueva Enterprise en runtime Community" 1 "$SCRIPT" apply
igual "conserva Actual ante ranura cruzada" 'local/odoo:19.0-desarrollo-utc-hash-2' \
  "$($SCRIPT get Actual | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])')"
python3 - "runtime/desarrollo/state/images.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["Nueva"] = None
data["Anterior"] = json.loads('''{"tag":"local/odoo:19.0-desarrollo-ee-hash","digest":"sha256:ee","odoo_version":"19.0","base_image":"odoo:19.0-20260810","infra_commit":"infra","edition":"enterprise","edition_tag":"19.0-ee-2026-09-14","enterprise_tag":"19.0-ee-2026-09-14","enterprise_commit":"ee","enterprise_modules":["ventas"],"addons":{"ventas":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"built_at":"20260914T120000Z"}''')
open(path, "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
sale_con "bloquea rollback hacia Enterprise" 1 "$SCRIPT" rollback

python3 - "runtime/desarrollo/state/images.json" "$PAYLOAD_EE" <<'PY'
import json, sys
path, payload = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
historica = json.loads(payload)
historica.pop("edition")
historica.pop("edition_tag")
historica.pop("enterprise_modules")
data["Nueva"] = historica
open(path, "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
ESTADO_HISTORICO=$(cat runtime/desarrollo/state/images.json)
contiene "show infiere edición Enterprise histórica" '"edition": "enterprise"' "$($SCRIPT show)"
contiene "show infiere tag Enterprise histórico" '"edition_tag": "19.0-ee-2026-09-14"' "$($SCRIPT show)"
contiene "infiere edición Enterprise histórica" '"edition": "enterprise"' "$($SCRIPT get Nueva)"
contiene "infiere tag Enterprise histórico" '"edition_tag": "19.0-ee-2026-09-14"' "$($SCRIPT get Nueva)"
igual "lector histórico no reescribe el estado" "$ESTADO_HISTORICO" "$(cat runtime/desarrollo/state/images.json)"

# Restore histórico
# Una fotografía Enterprise anterior a la feature se normaliza al restaurarla.
python3 - "$TMP/historic-images.json" <<'PY'
import json, sys
historical = {
    'tag': 'local/odoo:historico-ee', 'digest': 'sha256:historico',
    'odoo_version': '19.0', 'base_image': 'odoo:19.0-20260810',
    'infra_commit': 'infra', 'enterprise_tag': '19.0-ee-2026-09-14',
    'enterprise_commit': 'ee', 'addons': {},
    'built_at': '20260914T120000Z',
}
json.dump({'Nueva': None, 'Actual': historical, 'Anterior': None,
           'validation': None, 'rollback_blocked': False, 'module_operations': []},
          open(sys.argv[1], 'w', encoding='utf-8'))
PY
ENV_ANTES=$(cat runtime/desarrollo/compose.env)
python3 - runtime/desarrollo/compose.env <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = path.read_text(encoding='utf-8').splitlines()
lines = [
    'ODOO_EDITION=enterprise' if line.startswith('ODOO_EDITION=') else
    'TAG=19.0-ee-2026-09-14' if line.startswith('TAG=') else line
    for line in lines
]
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
sale_con "restore normaliza Enterprise histórico" 0 "$SCRIPT" restore-meta "$TMP/historic-images.json"
contiene "restore histórico infiere edición" '"edition": "enterprise"' "$($SCRIPT get Actual)"
contiene "restore histórico conserva tag Enterprise" '"edition_tag": "19.0-ee-2026-09-14"' "$($SCRIPT get Actual)"
printf '%s\n' "$ENV_ANTES" > runtime/desarrollo/compose.env

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
tar -cf "$TMP/runtime-after.tar" -C "$REPO_ROOT" runtime
igual "el test no modifica runtime preexistente" "0" "$(cmp -s "$TMP/runtime-before.tar" "$TMP/runtime-after.tar"; echo $?)"
resumen
