#!/usr/bin/env bash
# Verificación de promoción de addons
# Compara la selección ejecutada por staging con los candidatos productivos.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/contexto.sh
contexto_iniciar

# Alcance productivo
# El control se ejecuta después del PR y antes de aplicar cambios en producción.
if [[ "$ENTORNO" != produccion ]]; then
  printf 'promotion-verify: requiere ENTORNO=produccion\n' >&2
  exit 2
fi

# Rutas de procedencia
# Staging aporta su fotografía de arranque y producción sus candidatos independientes.
ROOT="$PWD"
STAGING_ENV="$ROOT/runtime/staging/compose.env"
STAGING_COMPOSE="$ROOT/runtime/staging/compose.yaml"
PRODUCTION_CANDIDATES="$ROOT/runtime/produccion/addons/custom"
ENTERPRISE_ROOT="$ROOT/runtime/produccion/addons/enterprise"
staging_edition=$(sed -n 's/^ODOO_EDITION=//p' "$STAGING_ENV" 2>/dev/null | tail -1)
staging_tag=$(sed -n 's/^TAG=//p' "$STAGING_ENV" 2>/dev/null | tail -1)
staging_compose() { docker compose --env-file "$STAGING_ENV" -f "$STAGING_COMPOSE" "$@"; }

# Estado ejecutado de staging
# Una configuración o candidato en disco no reemplaza un contenedor validado.
if [[ -z "$(staging_compose ps -q odoo 2>/dev/null)" ]]; then
  printf 'promotion-verify: staging no está operativo; levantarlo y ejecutar make verify\n' >&2
  exit 1
fi
staging_startup=$(staging_compose exec -T odoo cat /tmp/odoo-addons-startup.json 2>/dev/null) || {
  printf 'promotion-verify: staging no expone su selección cargada; recrearlo y ejecutar make verify\n' >&2
  exit 1
}

# Comparación de la promoción
# Python valida la fotografía cargada y compara los árboles publicados por ambos entornos.
python3 - "$staging_startup" "$staging_edition" "$staging_tag" \
  "$PRODUCTION_CANDIDATES" "$ODOO_EDITION" "$TAG" "$ENTERPRISE_ROOT" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

(startup_raw, staging_edition, staging_tag, candidates_root,
 production_edition, production_tag, enterprise_root) = sys.argv[1:]
candidates_root = pathlib.Path(candidates_root)
enterprise_root = pathlib.Path(enterprise_root)
object_pattern = re.compile(r"^[0-9a-f]{40,64}$")

def fail(message):
    raise SystemExit(f"promotion-verify: {message}")

try:
    startup = json.loads(startup_raw)
except json.JSONDecodeError:
    fail("la selección cargada de staging no es JSON válido")
if startup.get("entorno") != "staging" or startup.get("edition") != staging_edition:
    fail("la selección cargada de staging no coincide con su entorno o edición")
if staging_edition != production_edition or staging_tag != production_tag:
    fail("la edición o el tag productivo no coinciden con staging ejecutado")

addons = startup.get("addons")
if not isinstance(addons, dict):
    fail("staging ejecutado no tiene procedencia de addons")

if production_edition == "community":
    if startup.get("enterprise") is not None:
        fail("staging Community cargó procedencia Enterprise")
elif production_edition == "enterprise":
    enterprise = startup.get("enterprise")
    enterprise_commit = enterprise.get("commit") if isinstance(enterprise, dict) else None
    if not isinstance(enterprise, dict) or enterprise.get("tag") != production_tag or not isinstance(enterprise_commit, str) or not object_pattern.fullmatch(enterprise_commit):
        fail("la selección Enterprise ejecutada por staging es incompatible")
    try:
        production_enterprise = subprocess.check_output(
            ["git", "-C", str(enterprise_root), "rev-parse", "--verify", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        fail("producción no tiene un checkout Enterprise resoluble")
    if production_enterprise != enterprise_commit:
        fail("el commit Enterprise de producción no coincide con staging ejecutado")
else:
    fail("la edición productiva no es válida")

if not candidates_root.is_dir() and addons:
    fail("faltan los candidatos de producción")
production = {}
if candidates_root.is_dir():
    for candidate in candidates_root.iterdir():
        commit_marker = candidate / ".candidate-commit"
        tree_marker = candidate / ".candidate-tree"
        if candidate.is_dir() and commit_marker.is_file() and tree_marker.is_file():
            commit = commit_marker.read_text(encoding="utf-8").strip()
            tree = tree_marker.read_text(encoding="utf-8").strip()
            if not object_pattern.fullmatch(commit) or not object_pattern.fullmatch(tree):
                fail(f"el candidato productivo de {candidate.name} tiene marcadores inválidos")
            production[candidate.name] = {"commit": commit, "tree": tree}

if set(addons) != set(production):
    missing = sorted(set(addons) - set(production))
    extra = sorted(set(production) - set(addons))
    details = []
    if missing:
        details.append("faltan " + ", ".join(missing))
    if extra:
        details.append("sobran " + ", ".join(extra))
    fail("los dominios productivos no coinciden con staging: " + "; ".join(details))

for domain in sorted(addons):
    staging_value = addons[domain]
    if not isinstance(staging_value, dict) or not object_pattern.fullmatch(str(staging_value.get("commit", ""))) or not object_pattern.fullmatch(str(staging_value.get("tree", ""))):
        fail(f"staging tiene marcadores inválidos para {domain}")
    if staging_value["tree"] != production[domain]["tree"]:
        fail(f"el árbol de {domain} difiere entre staging ejecutado y producción")

print("promotion-verify: staging ejecutado coincide con los candidatos de producción")
PY
