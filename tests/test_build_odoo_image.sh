#!/usr/bin/env bash
# Contrato de construcción Odoo
# Verifica que la imagen contiene runtime y dependencias, pero nunca código de addons.
set -uo pipefail

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
REPO_ROOT="$PWD"
ROOT="$TMP/repo"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

# Checkout de infraestructura
# Conserva scripts y stack reales dentro de un repositorio temporal aislado.
mkdir -p "$ROOT/runtime/desarrollo" "$ROOT/runtime/addons" "$ROOT/stacks"
cp -R scripts "$ROOT/"
cp -R stacks/odoo "$ROOT/stacks/odoo"
cp runtime/desarrollo/compose.env.example "$ROOT/runtime/desarrollo/compose.env"
printf 'services: {}\n' > "$ROOT/runtime/desarrollo/compose.yaml"
: > "$ROOT/runtime/addons/requirements.override.txt"
: > "$ROOT/runtime/addons/catalogo.txt"
cd "$ROOT"
git init -q
git config user.email test@example.invalid
git config user.name test
git add scripts stacks runtime
git commit -qm base

# Repositorio custom
# La feature de desarrollo permite publicar varias revisiones y comparar huellas.
git -c init.defaultBranch=19.0 init -q "$TMP/ventas"
git -C "$TMP/ventas" config user.email test@example.invalid
git -C "$TMP/ventas" config user.name test
mkdir -p "$TMP/ventas/ventas"
printf "{'name': 'ventas', 'external_dependencies': {'python': ['authlib']}}\n" \
  > "$TMP/ventas/ventas/__manifest__.py"
printf 'authlib>=1.6.12,<1.7.0\n' > "$TMP/ventas/requirements.txt"
git -C "$TMP/ventas" add .
git -C "$TMP/ventas" commit -qm base
git -C "$TMP/ventas" checkout -qb feat/desarrollo
printf '%s\n' "$TMP/ventas" > runtime/addons/catalogo.txt

# Repositorio Enterprise
# Un tag anotado representa la selección privada del entorno.
git -c init.defaultBranch=main init -q "$TMP/enterprise"
git -C "$TMP/enterprise" config user.email test@example.invalid
git -C "$TMP/enterprise" config user.name test
mkdir -p "$TMP/enterprise/ventas_enterprise"
printf "{'name': 'ventas enterprise'}\n" > "$TMP/enterprise/ventas_enterprise/__manifest__.py"
git -C "$TMP/enterprise" add .
git -C "$TMP/enterprise" commit -qm inicial
git -C "$TMP/enterprise" tag -a 19.0-ee-2026-09-14 -m inmutable

# Docker controlado
# Registra el contexto y permite comprobar que un fallo no cambia el selector.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
if [ "${BUILD_FAIL:-0}" = 1 ] && [ "$1" = build ]; then exit 1; fi
if [ "$1" = image ] && [ "$2" = inspect ]; then printf 'sha256:build-digest\n'; fi
DOCKER
chmod +x "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH" DOCKER_CALLS="$TMP/docker-calls"
export ENTORNO=desarrollo ADDONS_REF=feat/desarrollo

# Selección inicial
# Los candidatos y Enterprise se preparan fuera del build como haría el operador.
igual "sync custom inicial termina bien" 0 "$(scripts/addons.sh sync >/dev/null 2>&1; echo $?)"
igual "sync Enterprise inicial termina bien" 0 \
  "$(scripts/addons.sh enterprise-sync "$TMP/enterprise" 19.0-ee-2026-09-14 >/dev/null 2>&1; echo $?)"
printf '%s\n' 'ODOO_EDITION=enterprise' 'TAG=19.0-ee-2026-09-14' >> runtime/desarrollo/compose.env

metadata_seleccionada() {
  local imagen
  imagen=$(sed -n 's/^ODOO_IMAGE=//p' runtime/desarrollo/compose.env | tail -1)
  find runtime/addons/builds/desarrollo -name image.json -type f -print | while IFS= read -r metadata; do
    grep -qF "\"tag\": \"$imagen\"" "$metadata" && printf '%s\n' "$metadata" && break
  done
}

salida=$(scripts/build-odoo-image.sh 2>&1); codigo=$?
igual "build Enterprise exitoso" 0 "$codigo"
contiene "publica el selector del entorno" 'Imagen Odoo seleccionada: local/odoo:19.0-desarrollo-' "$salida"
METADATA=$(metadata_seleccionada)
CONTENIDO=$(cat "$METADATA")
contiene "metadata conserva digest" 'sha256:build-digest' "$CONTENIDO"
contiene "metadata registra edición" '"edition": "enterprise"' "$CONTENIDO"
contiene "metadata registra odoo_base" '"odoo_base": "odoo:19.0-20260810"' "$CONTENIDO"
contiene "metadata registra huella de entradas" '"requirements_inputs_sha256": "' "$CONTENIDO"
contiene "metadata registra huella del lock" '"requirements_lock_sha256": "' "$CONTENIDO"
no_contiene "metadata no presenta commits custom como contenido" '"addons"' "$CONTENIDO"
no_contiene "metadata no presenta Enterprise como contenido" '"enterprise_commit"' "$CONTENIDO"

BUILD_DIR=$(dirname "$METADATA")
contiene "la fotografía resuelve requisitos custom" 'authlib>=1.6.12,<1.7.0' \
  "$(cat "$BUILD_DIR/requirements.lock.txt")"
igual "publica la misma huella de entradas en el runtime" \
  "$(cat "$BUILD_DIR/requirements.inputs.sha256")" \
  "$(cat runtime/desarrollo/addons/requirements.inputs.sha256)"
igual "publica la misma huella del lock en el runtime" \
  "$(cat "$BUILD_DIR/requirements.lock.sha256")" \
  "$(cat runtime/desarrollo/addons/requirements.lock.sha256)"

# Dockerfile sin addons
# La etapa final recibe wheels y entrypoint, pero ninguna carpeta de código.
DOCKERFILE=$(cat stacks/odoo/image/Dockerfile)
contiene "usa una etapa para compilar wheels" 'AS python-deps' "$DOCKERFILE"
contiene "copia wheels a la imagen final" 'COPY --from=python-deps /tmp/wheels/' "$DOCKERFILE"
no_contiene "no copia custom a la imagen" 'COPY custom/' "$DOCKERFILE"
no_contiene "no copia Enterprise a la imagen" 'COPY enterprise/' "$DOCKERFILE"

# Cambio exclusivo de código
# Un commit nuevo con las mismas declaraciones conserva ambas huellas de imagen.
INPUTS_INICIAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["requirements_inputs_sha256"])' "$METADATA")
LOCK_INICIAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["requirements_lock_sha256"])' "$METADATA")
printf "{'name': 'ventas v2', 'external_dependencies': {'python': ['authlib']}}\n" \
  > "$TMP/ventas/ventas/__manifest__.py"
git -C "$TMP/ventas" commit -qam 'solo código'
scripts/addons.sh sync >/dev/null
scripts/build-odoo-image.sh >/dev/null
METADATA_CODIGO=$(metadata_seleccionada)
igual "código solo conserva la huella de entradas" "$INPUTS_INICIAL" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["requirements_inputs_sha256"])' "$METADATA_CODIGO")"
igual "código solo conserva la huella del lock" "$LOCK_INICIAL" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["requirements_lock_sha256"])' "$METADATA_CODIGO")"

# Cambio de dependencias
# Una modificación de requirements produce una identidad de dependencias distinta.
printf 'authlib>=1.6.13,<1.7.0\n' > "$TMP/ventas/requirements.txt"
git -C "$TMP/ventas" commit -qam 'dependencia nueva'
scripts/addons.sh sync >/dev/null
scripts/build-odoo-image.sh >/dev/null
METADATA_DEPS=$(metadata_seleccionada)
INPUTS_DEPS=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["requirements_inputs_sha256"])' "$METADATA_DEPS")
igual "requirements cambia la identidad de entradas" 0 "$([ "$INPUTS_INICIAL" != "$INPUTS_DEPS" ]; echo $?)"

# Cambio de base
# La referencia FROM queda registrada y altera la identidad aunque los addons no cambien.
printf '%s\n' 'ODOO_EDITION=community' 'TAG=19.0-ce-2026-09-16' >> runtime/desarrollo/compose.env
sed -i.bak 's/odoo:19.0-20260810/odoo:20.0-20260810/g' stacks/odoo/image/Dockerfile
rm -f stacks/odoo/image/Dockerfile.bak
scripts/build-odoo-image.sh >/dev/null
METADATA_BASE=$(metadata_seleccionada)
contiene "la metadata refleja la base nueva" '"odoo_base": "odoo:20.0-20260810"' "$(cat "$METADATA_BASE")"

# Fallo de Docker
# El selector anterior permanece si la construcción no termina correctamente.
IMAGEN_ANTERIOR=$(sed -n 's/^ODOO_IMAGE=//p' runtime/desarrollo/compose.env | tail -1)
export BUILD_FAIL=1
sale_con "build fallido no reemplaza el selector" 1 scripts/build-odoo-image.sh
igual "build fallido conserva el selector" "$IMAGEN_ANTERIOR" \
  "$(sed -n 's/^ODOO_IMAGE=//p' runtime/desarrollo/compose.env | tail -1)"

resumen
