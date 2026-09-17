#!/usr/bin/env bash
# Verificación de promoción
# Ejercita la comparación entre staging validado y candidatos productivos en un checkout aislado.
set -euo pipefail

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

# Checkout temporal
# Copia solo el contrato que necesita el verificador y evita alterar estados reales.
ROOT="$TMP/infra"
mkdir -p "$ROOT/scripts/lib" "$ROOT/stacks/odoo/image" \
  "$ROOT/runtime/produccion/state" "$ROOT/runtime/staging/state" \
  "$ROOT/runtime/addons/custom/produccion" "$ROOT/runtime/addons/.repos"
cp scripts/promotion-verify.sh "$ROOT/scripts/"
cp scripts/lib/contexto.sh "$ROOT/scripts/lib/"
cp Makefile "$ROOT/"
cp -R .make "$ROOT/"
printf 'FROM odoo:19.0\n' > "$ROOT/stacks/odoo/image/Dockerfile"
printf 'services: {}\n' > "$ROOT/runtime/produccion/compose.yaml"
printf 'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' > "$ROOT/runtime/produccion/compose.env"
mkdir -p "$ROOT/runtime/staging"
printf 'services: {}\n' > "$ROOT/runtime/staging/compose.yaml"
printf 'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' > "$ROOT/runtime/staging/compose.env"

# Repositorio de dominio
# Dos commits permiten distinguir equivalencia de árbol y una divergencia real.
REPO="$ROOT/runtime/addons/.repos/ventas.git"
mkdir -p "$REPO"
git -C "$REPO" init -q -b 19.0
printf "{'name': 'ventas'}\n" > "$REPO/__manifest__.py"
git -C "$REPO" add __manifest__.py
git -C "$REPO" commit -qm base
BASE=$(git -C "$REPO" rev-parse HEAD)
printf 'cambio\n' >> "$REPO/__manifest__.py"
git -C "$REPO" commit -qam cambio
DIVERGENTE=$(git -C "$REPO" rev-parse HEAD)

estado_validado() {
  python3 - "$ROOT/runtime/staging/state/images.json" "$BASE" <<'PY'
import json, pathlib, sys
path, commit = map(pathlib.Path, sys.argv[1:])
payload = {
    "Nueva": None,
    "Actual": {
        "tag": "local/odoo:19.0-staging-test",
        "digest": "sha256:test",
        "odoo_version": "19.0",
        "base_image": "odoo:19.0",
        "infra_commit": "test",
        "edition": "community",
        "edition_tag": "19.0-ce-2026-09-16",
        "enterprise_tag": None,
        "enterprise_commit": None,
        "enterprise_modules": [],
        "addons": {"ventas": str(commit)},
        "built_at": "20260917T000000Z",
    },
    "Anterior": None,
    "validation": {"result": "ok", "note": "prueba", "at": "2026-09-17T00:00:00Z"},
    "rollback_blocked": False,
    "module_operations": [],
}
path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
}

ejecutar() { (cd "$ROOT" && ENTORNO=produccion scripts/promotion-verify.sh 2>&1); }
ejecutar_make() { (cd "$ROOT" && ENTORNO="${1:-produccion}" make promotion-verify 2>&1); }
codigo() {
  local salida retorno
  salida=$(ejecutar)
  retorno=$?
  [ "$retorno" -eq 0 ] || printf '%s\n' "$salida" >&2
  printf '%s' "$retorno"
}
codigo_make() {
  local salida retorno
  salida=$(ejecutar_make "${1:-produccion}")
  retorno=$?
  [ "$retorno" -eq 0 ] || printf '%s\n' "$salida" >&2
  printf '%s' "$retorno"
}

estado_validado
mkdir -p "$ROOT/runtime/addons/custom/produccion/ventas"
printf '%s\n' "$BASE" > "$ROOT/runtime/addons/custom/produccion/ventas/.candidate-commit"
igual "acepta árboles productivos equivalentes" "0" "$(codigo)"
printf '{"Actual":"sin cambios"}\n' > "$ROOT/runtime/produccion/state/images.json"
ESTADO_PRODUCCION=$(cat "$ROOT/runtime/produccion/state/images.json")
igual "el target exige producción" "2" "$(codigo_make staging)"
igual "el target verifica sin construir ni promover imágenes" "0" "$(codigo_make)"
igual "el target no altera el estado productivo" "$ESTADO_PRODUCCION" \
  "$(cat "$ROOT/runtime/produccion/state/images.json")"

rm -f "$ROOT/runtime/staging/state/images.json"
igual "falla si falta la imagen de staging" "1" "$(codigo)"

estado_validado
python3 - "$ROOT/runtime/staging/state/images.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
state = json.loads(path.read_text(encoding="utf-8"))
state["validation"] = None
path.write_text(json.dumps(state) + "\n", encoding="utf-8")
PY
igual "falla si staging no está validado" "1" "$(codigo)"

estado_validado
rm -rf "$ROOT/runtime/addons/custom/produccion/ventas"
igual "falla si falta un dominio productivo" "1" "$(codigo)"

mkdir -p "$ROOT/runtime/addons/custom/produccion/ventas"
printf '%s\n' "$DIVERGENTE" > "$ROOT/runtime/addons/custom/produccion/ventas/.candidate-commit"
igual "falla si el árbol del dominio diverge" "1" "$(codigo)"
igual "el target falla si producción no equivale a staging" "2" "$(codigo_make)"

printf '%s\n' "$BASE" > "$ROOT/runtime/addons/custom/produccion/ventas/.candidate-commit"
sed -i.bak 's/TAG=19.0-ce-2026-09-16/TAG=19.0-ce-2026-09-17/' "$ROOT/runtime/produccion/compose.env"
rm -f "$ROOT/runtime/produccion/compose.env.bak"
igual "falla si la edición productiva es incompatible" "1" "$(codigo)"

# Procedencia Enterprise
# La edición privada requiere que el checkout productivo conserve el commit validado.
ENTERPRISE="$ROOT/runtime/addons/enterprise"
mkdir -p "$ENTERPRISE"
git -C "$ENTERPRISE" init -q -b 19.0
printf 'enterprise\n' > "$ENTERPRISE/README"
git -C "$ENTERPRISE" add README
git -C "$ENTERPRISE" commit -qm enterprise
ENTERPRISE_COMMIT=$(git -C "$ENTERPRISE" rev-parse HEAD)
python3 - "$ROOT/runtime/staging/state/images.json" "$BASE" "$ENTERPRISE_COMMIT" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
addon_commit, enterprise_commit = sys.argv[2:]
state = json.loads(path.read_text(encoding="utf-8"))
actual = state["Actual"]
actual["edition"] = "enterprise"
actual["edition_tag"] = "19.0-ee-2026-09-16"
actual["enterprise_tag"] = "19.0-ee-2026-09-16"
actual["enterprise_commit"] = enterprise_commit
actual["enterprise_modules"] = ["ventas"]
actual["addons"] = {"ventas": addon_commit}
state["validation"] = {"result": "ok", "note": "enterprise", "at": "2026-09-17T00:00:00Z"}
path.write_text(json.dumps(state) + "\n", encoding="utf-8")
PY
sed -i.bak -e 's/ODOO_EDITION=community/ODOO_EDITION=enterprise/' -e 's/TAG=19.0-ce-2026-09-17/TAG=19.0-ee-2026-09-16/' "$ROOT/runtime/produccion/compose.env"
rm -f "$ROOT/runtime/produccion/compose.env.bak"
igual "acepta la procedencia Enterprise equivalente" "0" "$(codigo)"
printf 'distinto\n' >> "$ENTERPRISE/README"
git -C "$ENTERPRISE" commit -qam "enterprise distinto"
igual "falla si Enterprise no coincide con staging validado" "1" "$(codigo)"

resumen
