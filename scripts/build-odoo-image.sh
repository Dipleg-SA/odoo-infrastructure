#!/usr/bin/env bash
# Construcción de imagen Odoo
# Fotografía dependencias bajo el lock compartido sin copiar código de addons a la imagen.
set -euo pipefail
shopt -s nullglob

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/contexto.sh
. scripts/lib/candidate-lock.sh
contexto_iniciar

if [[ "${CANDIDATE_LOCK_HELD:-0}" != 1 ]]; then
  candidate_lock_run "$ENTORNO" -- env CANDIDATE_LOCK_HELD=1 "$0" "$@"
  exit $?
fi

# Fuentes y metadatos de la línea
# La imagen base se lee del Dockerfile, nunca de una rama de addons.
ROOT="$PWD"
ADDONS_ROOT="$ROOT/runtime/addons"
BUILD_ROOT="$ADDONS_ROOT/builds/$ENTORNO"
ENTERPRISE_ROOT="$RUNTIME_DIR/addons/enterprise"
CUSTOM_ROOT="$RUNTIME_DIR/addons/custom"
VERSION="$(contexto_odoo_version | head -1)"
BASE_IMAGE="$(sed -n 's/^[[:space:]]*FROM[[:space:]]*\([^[:space:]]*\).*$/\1/p' stacks/odoo/image/Dockerfile | head -1)"

fail() { printf 'build-odoo-image: %s\n' "$1" >&2; exit 1; }
[[ -n "$VERSION" && -n "$BASE_IMAGE" ]] || fail 'no se pudo resolver la línea o imagen base de Odoo'

# Selección de edición
# Community ignora cualquier checkout Enterprise residual; Enterprise exige su snapshot privado.
case "$ODOO_EDITION" in
  community) ;;
  enterprise)
    [[ -d "$ENTERPRISE_ROOT/.git" ]] || fail "falta runtime/$ENTORNO/addons/enterprise; ejecutar enterprise sync"
    ;;
  *)
    fail "edición no soportada: $ODOO_EDITION"
    ;;
esac
CANDIDATE_LOCK_HELD=1 scripts/addons-runtime.sh validate >/dev/null \
  || fail 'los addons seleccionados no superan la validación de integridad'

# Fotografía de dependencias
# El código se exporta a un contexto temporal solo para resolver sus declaraciones.
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
MOMENTO="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BUILD_ROOT"
TEMP_BUILD=$(mktemp -d "$BUILD_ROOT/.build.XXXXXX")
trap 'rm -rf "${TEMP_BUILD:-}"' EXIT
mkdir -p "$TEMP_BUILD/enterprise" "$TEMP_BUILD/custom"
if [[ "$ODOO_EDITION" == enterprise ]]; then
  git -C "$ENTERPRISE_ROOT" archive --format=tar HEAD | tar -xf - -C "$TEMP_BUILD/enterprise"
fi
for candidato in "$CUSTOM_ROOT"/*; do
  [[ -d "$candidato" ]] || continue
  dominio="$(basename "$candidato")"
  commit="$(cat "$candidato/.candidate-commit" 2>/dev/null || true)"
  [[ "$commit" =~ ^[0-9a-f]{40,64}$ ]] || fail "candidato inválido para $dominio"
  mkdir -p "$TEMP_BUILD/custom/$dominio"
  git -C "$ADDONS_ROOT/.repos/$dominio.git" archive --format=tar "$commit" \
    | tar -xf - -C "$TEMP_BUILD/custom/$dominio"
done

# Compilación de dependencias
# Las huellas resultantes, no los commits de addons, determinan la identidad de imagen.
cp stacks/odoo/image/Dockerfile stacks/odoo/image/entrypoint.sh "$TEMP_BUILD/"
PYDEPS_SNAPSHOT_ROOT="$TEMP_BUILD" scripts/pydeps.sh check
PYDEPS_SNAPSHOT_ROOT="$TEMP_BUILD" PYDEPS_OUTPUT="$TEMP_BUILD/requirements.lock.txt" scripts/pydeps.sh compile
INPUTS_HASH=$(cat "$TEMP_BUILD/requirements.inputs.sha256")
LOCK_HASH=$(cat "$TEMP_BUILD/requirements.lock.sha256")
FOTOGRAFIA="$(printf 'odoo_base=%s\nedition=%s\ninputs=%s\nlock=%s\n' \
  "$BASE_IMAGE" "$ODOO_EDITION" "$INPUTS_HASH" "$LOCK_HASH" | sha256 | cut -c1-16)"
IDENTIFICADOR="${MOMENTO}-${FOTOGRAFIA}"
BUILD_DIR="$BUILD_ROOT/$IDENTIFICADOR"
IMAGE_TAG="local/odoo:${VERSION}-${ENTORNO}-${MOMENTO}-${FOTOGRAFIA}"
rm -rf "$BUILD_DIR"
mv "$TEMP_BUILD" "$BUILD_DIR"
TEMP_BUILD=""

# Build y digest
# El selector no cambia si Docker no construye o no devuelve una identidad.
docker build --tag "$IMAGE_TAG" "$BUILD_DIR"
DIGEST="$(docker image inspect --format '{{.RepoDigests}}' "$IMAGE_TAG" 2>/dev/null | tr -d '[]' | awk '{print $1}')"
[[ -n "$DIGEST" ]] || DIGEST="$(docker image inspect --format '{{.Id}}' "$IMAGE_TAG" 2>/dev/null || true)"
[[ -n "$DIGEST" ]] || fail 'el build terminó sin digest identificable; ODOO_IMAGE no fue modificado'

# Procedencia y publicación
# La procedencia queda junto a la fotografía para facilitar diagnóstico.
METADATA="$BUILD_DIR/image.json"
python3 - "$METADATA" "$IMAGE_TAG" "$DIGEST" "$VERSION" "$BASE_IMAGE" "$ODOO_EDITION" "$TAG" \
  "$INPUTS_HASH" "$LOCK_HASH" "$ROOT" "$MOMENTO" <<'PY'
import json, pathlib, subprocess, sys
out, tag, digest, version, base, edition, edition_tag, inputs_hash, lock_hash, root, built_at = sys.argv[1:]
infra = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip()
payload = {"tag": tag, "digest": digest, "odoo_version": version, "odoo_base": base,
           "infra_commit": infra, "edition": edition, "edition_tag": edition_tag,
           "requirements_inputs_sha256": inputs_hash,
           "requirements_lock_sha256": lock_hash, "built_at": built_at}
pathlib.Path(out).write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
PY

# Huellas seleccionadas
# Se publican solo después de un build exitoso para que el preflight compare el mismo snapshot.
install -m 0644 "$BUILD_DIR/requirements.lock.txt" "$RUNTIME_DIR/addons/requirements.lock.txt"
install -m 0644 "$BUILD_DIR/requirements.inputs.sha256" "$RUNTIME_DIR/addons/requirements.inputs.sha256"
install -m 0644 "$BUILD_DIR/requirements.lock.sha256" "$RUNTIME_DIR/addons/requirements.lock.sha256"

# Selector único del runtime
# La sustitución atómica conserva la referencia anterior si el build falló.
python3 - "$RUNTIME_ENV_FILE" "$IMAGE_TAG" <<'PY'
import os
import pathlib
import tempfile
import sys

path, tag = map(pathlib.Path, sys.argv[1:])
lines = path.read_text(encoding="utf-8").splitlines()
replacement = f"ODOO_IMAGE={tag}"
for index, line in enumerate(lines):
    if line.startswith("ODOO_IMAGE="):
        lines[index] = replacement
        break
else:
    lines.extend(["", "# Imagen Odoo", "# Referencia seleccionada por make build.", replacement])

fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        output.write("\n".join(lines) + "\n")
    os.replace(temporary, path)
except BaseException:
    os.unlink(temporary)
    raise
PY
printf 'Imagen Odoo seleccionada: %s\n' "$IMAGE_TAG"
