#!/usr/bin/env bash
# Verificación de promoción de código
# Compara candidatos productivos con la selección que staging cargó al arrancar.
set -uo pipefail

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

# Checkout mínimo
# El stub de Docker representa exclusivamente el estado y el inventario de staging.
ROOT="$TMP/infra"
BIN="$TMP/bin"
mkdir -p "$ROOT/scripts/lib" "$ROOT/runtime/produccion/addons/custom/ventas" \
  "$ROOT/runtime/staging" "$BIN"
cp scripts/promotion-verify.sh "$ROOT/scripts/"
cp scripts/lib/contexto.sh "$ROOT/scripts/lib/"
cp Makefile "$ROOT/"
cp -R .make "$ROOT/"
printf 'services: {}\n' > "$ROOT/runtime/produccion/compose.yaml"
printf 'services: {}\n' > "$ROOT/runtime/staging/compose.yaml"
printf 'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' > "$ROOT/runtime/produccion/compose.env"
printf 'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' > "$ROOT/runtime/staging/compose.env"
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PROMOTION_STUB/llamadas"
case "$*" in
  *"ps -q odoo"*) [ ! -f "$PROMOTION_STUB/staging-down" ] && printf '%s\n' staging-id ;;
  *"cat /tmp/odoo-addons-startup.json"*) cat "$PROMOTION_STUB/startup.json" ;;
  *) exit 0 ;;
esac
EOF
chmod 755 "$BIN/docker"
export PROMOTION_STUB="$TMP/stub"
mkdir -p "$PROMOTION_STUB"

# Árboles custom
# El commit puede avanzar sin validación, pero la promoción compara la huella ejecutada.
COMMIT_STAGING=$(printf '1%.0s' {1..40})
COMMIT_NUEVO=$(printf '2%.0s' {1..40})
TREE_STAGING=$(printf 'a%.0s' {1..40})
TREE_NUEVO=$(printf 'b%.0s' {1..40})
printf '%s\n' "$COMMIT_STAGING" > "$ROOT/runtime/produccion/addons/custom/ventas/.candidate-commit"
printf '%s\n' "$TREE_STAGING" > "$ROOT/runtime/produccion/addons/custom/ventas/.candidate-tree"

escribir_startup() {
  python3 - "$PROMOTION_STUB/startup.json" "$1" "$2" "$3" "$4" <<'PY'
import json, pathlib, sys
path, edition, tag, commit, tree = sys.argv[1:]
enterprise = None
if edition == "enterprise":
    enterprise = {"tag": tag, "commit": commit}
    addons = {"ventas": {"commit": "1" * 40, "tree": tree}}
else:
    addons = {"ventas": {"commit": commit, "tree": tree}}
payload = {"entorno": "staging", "edition": edition, "addons": addons, "enterprise": enterprise}
pathlib.Path(path).write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
}

ejecutar() { (cd "$ROOT" && ENTORNO=produccion PATH="$BIN:$PATH" scripts/promotion-verify.sh 2>&1); }
ejecutar_make() { (cd "$ROOT" && ENTORNO=produccion PATH="$BIN:$PATH" make promotion-verify 2>&1); }
codigo() { local salida retorno; salida=$(ejecutar); retorno=$?; [ "$retorno" -eq 0 ] || printf '%s\n' "$salida" >&2; printf '%s' "$retorno"; }

titulo "promotion-verify — selección ejecutada"
escribir_startup community 19.0-ce-2026-09-16 "$COMMIT_STAGING" "$TREE_STAGING"
igual "acepta el árbol que staging ejecutó" "0" "$(codigo)"
igual "el target Make verifica producción" "0" "$(ejecutar_make >/dev/null 2>&1; echo $?)"

printf '%s\n' "$COMMIT_NUEVO" > "$ROOT/runtime/produccion/addons/custom/ventas/.candidate-commit"
printf '%s\n' "$TREE_NUEVO" > "$ROOT/runtime/produccion/addons/custom/ventas/.candidate-tree"
igual "rechaza un candidato más nuevo no probado" "1" "$(codigo)"
printf '%s\n' "$COMMIT_STAGING" > "$ROOT/runtime/produccion/addons/custom/ventas/.candidate-commit"
printf '%s\n' "$TREE_STAGING" > "$ROOT/runtime/produccion/addons/custom/ventas/.candidate-tree"

touch "$PROMOTION_STUB/staging-down"
salida=$(ejecutar); codigo_salida=$?
igual "rechaza staging detenido" "1" "$codigo_salida"
contiene "explica que staging debe estar operativo" "staging no está operativo" "$salida"
rm "$PROMOTION_STUB/staging-down"

# Enterprise por entorno
# Producción se compara con el commit cargado, nunca con un checkout compartido.
ENTERPRISE="$ROOT/runtime/produccion/addons/enterprise"
mkdir -p "$ENTERPRISE"
git -C "$ENTERPRISE" init -q -b 19.0
printf 'enterprise\n' > "$ENTERPRISE/README"
git -C "$ENTERPRISE" add README
git -C "$ENTERPRISE" commit -qm enterprise
ENTERPRISE_COMMIT=$(git -C "$ENTERPRISE" rev-parse HEAD)
sed -i.bak -e 's/ODOO_EDITION=community/ODOO_EDITION=enterprise/' -e 's/TAG=19.0-ce-2026-09-16/TAG=19.0-ee-2026-09-16/' "$ROOT/runtime/produccion/compose.env"
sed -i.bak -e 's/ODOO_EDITION=community/ODOO_EDITION=enterprise/' -e 's/TAG=19.0-ce-2026-09-16/TAG=19.0-ee-2026-09-16/' "$ROOT/runtime/staging/compose.env"
rm -f "$ROOT/runtime/produccion/compose.env.bak" "$ROOT/runtime/staging/compose.env.bak"
escribir_startup enterprise 19.0-ee-2026-09-16 "$ENTERPRISE_COMMIT" "$TREE_STAGING"
igual "acepta Enterprise independiente equivalente" "0" "$(codigo)"
printf 'distinto\n' >> "$ENTERPRISE/README"
git -C "$ENTERPRISE" commit -qam "enterprise distinto"
igual "rechaza Enterprise productivo distinto del ejecutado" "1" "$(codigo)"

resumen
