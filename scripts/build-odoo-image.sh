#!/usr/bin/env bash
# Construcción de imagen Odoo inmutable
# Fotografía Community o Enterprise y candidatos bajo el lock compartido antes de publicar Nueva.
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
ENTERPRISE_ROOT="$ADDONS_ROOT/enterprise"
ENTERPRISE_TAG="${ENTERPRISE_TAG:-}"
VERSION="$(contexto_odoo_version | head -1)"
BASE_IMAGE="$(sed -n 's/^[[:space:]]*FROM[[:space:]]*\([^[:space:]]*\).*$/\1/p' stacks/odoo/image/Dockerfile | head -1)"

fail() { printf 'build-odoo-image: %s\n' "$1" >&2; exit 1; }
[[ -n "$VERSION" && -n "$BASE_IMAGE" ]] || fail 'no se pudo resolver la línea o imagen base de Odoo'

# Selección de edición
# Community ignora cualquier checkout Enterprise residual; Enterprise exige su snapshot privado.
case "$ODOO_EDITION" in
  community)
    ENTERPRISE_TAG=""
    ;;
  enterprise)
    ENTERPRISE_TAG="$TAG"
    [[ -d "$ENTERPRISE_ROOT/.git" ]] || fail 'falta runtime/addons/enterprise; ejecutar enterprise sync'
    scripts/addons.sh enterprise-validate "$ENTERPRISE_TAG" >/dev/null || fail 'Enterprise no coincide con el tag seleccionado'
    ;;
  *)
    fail "edición no soportada: $ODOO_EDITION"
    ;;
esac

# Fotografía de commits
# Cada dominio se lee desde el marcador publicado por addons.sh.
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
ENTERPRISE_COMMIT=""
if [[ "$ODOO_EDITION" == enterprise ]]; then
  ENTERPRISE_COMMIT="$(git -C "$ENTERPRISE_ROOT" rev-parse HEAD)"
fi
DOMAINS=()
COMMITS=()
for candidato in "$ADDONS_ROOT/custom/$ENTORNO"/*; do
  [[ -d "$candidato" ]] || continue
  dominio="$(basename "$candidato")"
  commit="$(cat "$candidato/.candidate-commit" 2>/dev/null || true)"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || fail "candidato inválido para $dominio"
  DOMAINS+=("$dominio")
  COMMITS+=("$commit")
done
FOTOGRAFIA="$( { printf 'edition=%s\nedition_tag=%s\nversion=%s\nenterprise_tag=%s\nenterprise_commit=%s\n' "$ODOO_EDITION" "$TAG" "$VERSION" "$ENTERPRISE_TAG" "$ENTERPRISE_COMMIT"; for i in "${!DOMAINS[@]}"; do printf '%s=%s\n' "${DOMAINS[$i]}" "${COMMITS[$i]}"; done | sort; } | sha256 | cut -c1-16)"
MOMENTO="$(date -u +%Y%m%dT%H%M%SZ)"
IDENTIFICADOR="${MOMENTO}-${FOTOGRAFIA}"
BUILD_DIR="$BUILD_ROOT/$IDENTIFICADOR"
IMAGE_TAG="local/odoo:${VERSION}-${ENTORNO}-${MOMENTO}-${FOTOGRAFIA}"

# Exportación estable del contexto
# El build solo recibe archivos extraídos de los SHAs ya publicados.
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/enterprise" "$BUILD_DIR/custom"
if [[ "$ODOO_EDITION" == enterprise ]]; then
  git -C "$ENTERPRISE_ROOT" archive --format=tar HEAD | tar -xf - -C "$BUILD_DIR/enterprise"
fi
for i in "${!DOMAINS[@]}"; do
  dominio="${DOMAINS[$i]}"
  mkdir -p "$BUILD_DIR/custom/$dominio"
  git -C "$ADDONS_ROOT/.repos/$dominio.git" archive --format=tar "${COMMITS[$i]}" | tar -xf - -C "$BUILD_DIR/custom/$dominio"
done

# Inventario técnico Enterprise
# Los módulos se derivan del snapshot que realmente recibe Docker y no del checkout completo.
ENTERPRISE_MODULES=""
if [[ "$ODOO_EDITION" == enterprise ]]; then
  ENTERPRISE_MODULES="$(find "$BUILD_DIR/enterprise" -type f -name __manifest__.py -print | while IFS= read -r manifest; do basename "$(dirname "$manifest")"; done | sort -u)"
fi
cp stacks/odoo/image/Dockerfile stacks/odoo/image/entrypoint.sh "$BUILD_DIR/"
PYDEPS_SNAPSHOT_ROOT="$BUILD_DIR" scripts/pydeps.sh check
PYDEPS_SNAPSHOT_ROOT="$BUILD_DIR" PYDEPS_OUTPUT="$BUILD_DIR/requirements.lock.txt" scripts/pydeps.sh compile

# Build y digest
# Nueva no cambia si Docker no construye o no devuelve una identidad.
docker build --tag "$IMAGE_TAG" "$BUILD_DIR"
DIGEST="$(docker image inspect --format '{{.RepoDigests}}' "$IMAGE_TAG" 2>/dev/null | tr -d '[]' | awk '{print $1}')"
[[ -n "$DIGEST" ]] || DIGEST="$(docker image inspect --format '{{.Id}}' "$IMAGE_TAG" 2>/dev/null || true)"
[[ -n "$DIGEST" ]] || fail 'el build terminó sin digest identificable; Nueva no fue modificada'

# Procedencia y publicación
# El estado se escribe una sola vez, después de build y digest exitosos.
METADATA="$BUILD_DIR/image.json"
python3 - "$METADATA" "$IMAGE_TAG" "$DIGEST" "$VERSION" "$BASE_IMAGE" "$ODOO_EDITION" "$TAG" "$ENTERPRISE_TAG" "$ENTERPRISE_COMMIT" "$ENTERPRISE_MODULES" "$ROOT" "$ENTORNO" "$MOMENTO" <<'PY'
import json, pathlib, subprocess, sys
out, tag, digest, version, base, edition, edition_tag, ee_tag, ee_commit, ee_modules, root, env, built_at = sys.argv[1:]
addons_root = pathlib.Path(root, "runtime", "addons", "custom", env)
addons = {p.parent.name: p.read_text(encoding="utf-8").strip() for p in addons_root.glob("*/.candidate-commit")}
infra = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip()
enterprise_modules = sorted(filter(None, ee_modules.splitlines()))
payload = {"tag": tag, "digest": digest, "odoo_version": version, "base_image": base, "infra_commit": infra,
           "edition": edition, "edition_tag": edition_tag,
           "enterprise_tag": ee_tag or None, "enterprise_commit": ee_commit or None,
           "enterprise_modules": enterprise_modules, "addons": dict(sorted(addons.items())), "built_at": built_at}
pathlib.Path(out).write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
PY
scripts/image-state.sh write-new "$METADATA"
printf 'Nueva registrada: %s\n' "$IMAGE_TAG"
