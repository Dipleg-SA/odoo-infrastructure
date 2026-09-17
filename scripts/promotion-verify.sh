#!/usr/bin/env bash
# Verificación de promoción de addons
# Compara candidatos productivos con la imagen de staging validada sin modificar ningún estado.
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
# La fotografía de staging y los candidatos de producción comparten los clones bare.
ROOT="$PWD"
STAGING_STATE="$ROOT/runtime/staging/state/images.json"
PRODUCTION_CANDIDATES="$ROOT/runtime/addons/custom/produccion"
BARE_DIR="$ROOT/runtime/addons/.repos"
ENTERPRISE_ROOT="$ROOT/runtime/addons/enterprise"

# Comparación de la promoción
# Python valida la fotografía y compara árboles Git, no solo SHAs que pueden reescribirse.
python3 - "$STAGING_STATE" "$PRODUCTION_CANDIDATES" "$BARE_DIR" "$ODOO_EDITION" "$TAG" "$ENTERPRISE_ROOT" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

state_path, candidates_root, bare_dir, edition, edition_tag, enterprise_root = map(pathlib.Path, sys.argv[1:])
edition = str(edition)
edition_tag = str(edition_tag)
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

if not state_path.is_file():
    fail("falta runtime/staging/state/images.json")
try:
    state = json.loads(state_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"no se pudo leer la imagen de staging: {error}")

actual = state.get("Actual")
validation = state.get("validation")
if not isinstance(actual, dict):
    fail("staging no tiene una imagen Actual")
if not isinstance(validation, dict) or validation.get("result") != "ok":
    fail("la imagen Actual de staging no está validada")

addons = actual.get("addons")
if not isinstance(addons, dict):
    fail("la imagen Actual de staging no tiene procedencia de addons")
if actual.get("edition") != edition or actual.get("edition_tag") != edition_tag:
    fail("la edición o el tag productivo no coinciden con staging validado")

if edition == "community":
    if actual.get("enterprise_tag") not in (None, "") or actual.get("enterprise_commit") not in (None, ""):
        fail("staging Community conserva procedencia Enterprise")
elif edition == "enterprise":
    enterprise_commit = actual.get("enterprise_commit")
    if actual.get("enterprise_tag") != edition_tag or not isinstance(enterprise_commit, str) or not commit_pattern.fullmatch(enterprise_commit):
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
        fail("el commit Enterprise de producción no coincide con staging validado")
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
        fail(f"el árbol de {domain} difiere entre staging validado y producción")

print("promotion-verify: staging validado coincide con los candidatos de producción")
PY
