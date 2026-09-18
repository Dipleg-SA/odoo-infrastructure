#!/usr/bin/env bash
# Verificación de promoción de addons
# Compara el build seleccionado de staging con candidatos productivos sin estado de imágenes.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/contexto.sh
contexto_iniciar

# Alcance productivo
# El control se ejecuta después del PR y antes del build de producción.
if [[ "$ENTORNO" != produccion ]]; then
  printf 'promotion-verify: requiere ENTORNO=produccion\n' >&2
  exit 2
fi

# Rutas de procedencia
# La metadata del build seleccionado conserva los commits que staging ejecutó.
ROOT="$PWD"
STAGING_ENV="$ROOT/runtime/staging/compose.env"
STAGING_BUILDS="$ROOT/runtime/addons/builds/staging"
PRODUCTION_CANDIDATES="$ROOT/runtime/addons/custom/produccion"
BARE_DIR="$ROOT/runtime/addons/.repos"
ENTERPRISE_ROOT="$ROOT/runtime/addons/enterprise"

staging_image=$(sed -n 's/^ODOO_IMAGE=//p' "$STAGING_ENV" 2>/dev/null | tail -1)
staging_edition=$(sed -n 's/^ODOO_EDITION=//p' "$STAGING_ENV" 2>/dev/null | tail -1)
staging_tag=$(sed -n 's/^TAG=//p' "$STAGING_ENV" 2>/dev/null | tail -1)

# Comparación de la promoción
# Python valida la metadata seleccionada y compara árboles Git, no solo referencias.
python3 - "$STAGING_BUILDS" "$staging_image" "$staging_edition" "$staging_tag" \
  "$PRODUCTION_CANDIDATES" "$BARE_DIR" "$ODOO_EDITION" "$TAG" "$ENTERPRISE_ROOT" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

(builds_root, selected_image, staging_edition, staging_tag, candidates_root,
 bare_dir, production_edition, production_tag, enterprise_root) = sys.argv[1:]
builds_root = pathlib.Path(builds_root)
candidates_root = pathlib.Path(candidates_root)
bare_dir = pathlib.Path(bare_dir)
enterprise_root = pathlib.Path(enterprise_root)
commit_pattern = re.compile(r"^[0-9a-f]{40}$")

def fail(message):
    raise SystemExit(f"promotion-verify: {message}")

def tree(repository, commit, label):
    if not repository.is_dir():
        fail(f"falta el clon bare de {label}")
    try:
        value = subprocess.check_output(
            ["git", "-C", str(repository), "rev-parse", "--verify", f"{commit}^{{tree}}"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        fail(f"{label} no resuelve el árbol del commit {commit}")
    if not commit_pattern.fullmatch(value):
        fail(f"{label} devolvió un árbol inválido")
    return value

if not selected_image:
    fail("staging no tiene ODOO_IMAGE seleccionada")
metadata = None
for path in sorted(builds_root.glob("*/image.json")):
    try:
        candidate = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        continue
    if candidate.get("tag") == selected_image:
        metadata = candidate
        break
if not isinstance(metadata, dict):
    fail("no se encontró metadata para la ODOO_IMAGE seleccionada de staging")

if metadata.get("edition") != staging_edition or metadata.get("edition_tag") != staging_tag:
    fail("la metadata de staging no coincide con su configuración de edición")
if staging_edition != production_edition or staging_tag != production_tag:
    fail("la edición o el tag productivo no coinciden con staging seleccionado")

addons = metadata.get("addons")
if not isinstance(addons, dict):
    fail("el build seleccionado de staging no tiene procedencia de addons")

if production_edition == "community":
    if metadata.get("enterprise_tag") not in (None, "") or metadata.get("enterprise_commit") not in (None, ""):
        fail("staging Community conserva procedencia Enterprise")
elif production_edition == "enterprise":
    enterprise_commit = metadata.get("enterprise_commit")
    if metadata.get("enterprise_tag") != production_tag or not isinstance(enterprise_commit, str) or not commit_pattern.fullmatch(enterprise_commit):
        fail("la procedencia Enterprise de staging es incompatible")
    try:
        production_enterprise = subprocess.check_output(
            ["git", "-C", str(enterprise_root), "rev-parse", "--verify", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except subprocess.CalledProcessError:
        fail("producción no tiene un checkout Enterprise resoluble")
    if production_enterprise != enterprise_commit:
        fail("el commit Enterprise de producción no coincide con staging seleccionado")
else:
    fail("la edición productiva no es válida")

if not candidates_root.is_dir() and addons:
    fail("faltan los candidatos de producción")
production = {}
if candidates_root.is_dir():
    for candidate in candidates_root.iterdir():
        marker = candidate / ".candidate-commit"
        if candidate.is_dir() and marker.is_file():
            commit = marker.read_text(encoding="utf-8").strip()
            if not commit_pattern.fullmatch(commit):
                fail(f"el candidato productivo de {candidate.name} tiene un commit inválido")
            production[candidate.name] = commit

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
    staging_commit = addons[domain]
    if not isinstance(staging_commit, str) or not commit_pattern.fullmatch(staging_commit):
        fail(f"staging tiene un commit inválido para {domain}")
    repository = bare_dir / f"{domain}.git"
    if tree(repository, staging_commit, f"staging/{domain}") != tree(repository, production[domain], f"producción/{domain}"):
        fail(f"el árbol de {domain} difiere entre staging seleccionado y producción")

print("promotion-verify: staging seleccionado coincide con los candidatos de producción")
