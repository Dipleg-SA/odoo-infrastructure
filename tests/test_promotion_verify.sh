#!/usr/bin/env bash
# Verificación de promoción de código
# Compara la metadata del build seleccionado de staging con candidatos productivos.
set -uo pipefail

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

ROOT="$TMP/infra"
mkdir -p "$ROOT/scripts/lib" "$ROOT/runtime/produccion" "$ROOT/runtime/staging" \
  "$ROOT/runtime/addons/builds/staging/seleccionada" "$ROOT/runtime/addons/custom/produccion" \
  "$ROOT/runtime/addons/.repos"
cp scripts/promotion-verify.sh "$ROOT/scripts/"
cp scripts/lib/contexto.sh "$ROOT/scripts/lib/"
cp Makefile "$ROOT/"
cp -R .make "$ROOT/"
printf 'services: {}\n' > "$ROOT/runtime/produccion/compose.yaml"
printf 'services: {}\n' > "$ROOT/runtime/staging/compose.yaml"
printf 'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' > "$ROOT/runtime/produccion/compose.env"
printf 'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\nODOO_IMAGE=local/odoo:19.0-staging-20260917T183719Z-fa588059f4932d2f\n' \
  > "$ROOT/runtime/staging/compose.env"

# Repositorio bare de dominio
# Dos commits permiten distinguir equivalencia de árbol y divergencia real.
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

escribir_metadata() {
  python3 - "$ROOT/runtime/addons/builds/staging/seleccionada/image.json" "$1" "$2" "$3" "$BASE" <<'PY'
import json, pathlib, sys
path, edition, tag, enterprise_commit, addon_commit = sys.argv[1:]
payload = {
    "tag": "local/odoo:19.0-staging-20260917T183719Z-fa588059f4932d2f",
    "edition": edition,
    "edition_tag": tag,
    "enterprise_tag": tag if edition == "enterprise" else None,
    "enterprise_commit": enterprise_commit if edition == "enterprise" else None,
    "addons": {"ventas": addon_commit},
}
pathlib.Path(path).write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
}

ejecutar() { (cd "$ROOT" && ENTORNO=produccion scripts/promotion-verify.sh 2>&1); }
ejecutar_make() { (cd "$ROOT" && ENTORNO=produccion make promotion-verify 2>&1); }
codigo() { local salida retorno; salida=$(ejecutar); retorno=$?; [ "$retorno" -eq 0 ] || printf '%s\n' "$salida" >&2; printf '%s' "$retorno"; }

escribir_metadata community 19.0-ce-2026-09-16 ""
mkdir -p "$ROOT/runtime/addons/custom/produccion/ventas"
printf '%s\n' "$BASE" > "$ROOT/runtime/addons/custom/produccion/ventas/.candidate-commit"
igual "acepta árboles productivos equivalentes" "0" "$(codigo)"
igual "el target Make verifica producción" "0" "$(ejecutar_make >/dev/null 2>&1; echo $?)"

printf '%s\n' "$DIVERGENTE" > "$ROOT/runtime/addons/custom/produccion/ventas/.candidate-commit"
igual "falla si el árbol del dominio diverge" "1" "$(codigo)"
printf '%s\n' "$BASE" > "$ROOT/runtime/addons/custom/produccion/ventas/.candidate-commit"

rm -f "$ROOT/runtime/addons/builds/staging/seleccionada/image.json"
igual "falla si falta metadata del build de staging" "1" "$(codigo)"
mkdir -p "$ROOT/runtime/addons/builds/staging/seleccionada"
escribir_metadata community 19.0-ce-2026-09-16 ""

sed -i.bak 's/TAG=19.0-ce-2026-09-16/TAG=19.0-ce-2026-09-17/' "$ROOT/runtime/produccion/compose.env"
rm -f "$ROOT/runtime/produccion/compose.env.bak"
igual "falla si la edición productiva difiere" "1" "$(codigo)"
sed -i.bak 's/TAG=19.0-ce-2026-09-17/TAG=19.0-ce-2026-09-16/' "$ROOT/runtime/produccion/compose.env"
rm -f "$ROOT/runtime/produccion/compose.env.bak"

# Procedencia Enterprise
# El build privado y el checkout productivo deben conservar el mismo commit.
ENTERPRISE="$ROOT/runtime/addons/enterprise"
mkdir -p "$ENTERPRISE"
git -C "$ENTERPRISE" init -q -b 19.0
printf 'enterprise\n' > "$ENTERPRISE/README"
git -C "$ENTERPRISE" add README
git -C "$ENTERPRISE" commit -qm enterprise
ENTERPRISE_COMMIT=$(git -C "$ENTERPRISE" rev-parse HEAD)
sed -i.bak -e 's/ODOO_EDITION=community/ODOO_EDITION=enterprise/' -e 's/TAG=19.0-ce-2026-09-16/TAG=19.0-ee-2026-09-16/' "$ROOT/runtime/produccion/compose.env"
sed -i.bak -e 's/ODOO_EDITION=community/ODOO_EDITION=enterprise/' -e 's/TAG=19.0-ce-2026-09-16/TAG=19.0-ee-2026-09-16/' "$ROOT/runtime/staging/compose.env"
rm -f "$ROOT/runtime/produccion/compose.env.bak" "$ROOT/runtime/staging/compose.env.bak"
escribir_metadata enterprise 19.0-ee-2026-09-16 "$ENTERPRISE_COMMIT"
igual "acepta la procedencia Enterprise equivalente" "0" "$(codigo)"
printf 'distinto\n' >> "$ENTERPRISE/README"
git -C "$ENTERPRISE" commit -qam "enterprise distinto"
igual "falla si Enterprise no coincide con staging" "1" "$(codigo)"

resumen
