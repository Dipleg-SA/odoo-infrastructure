#!/usr/bin/env bash
# Contrato de fotografía Odoo
# Construye con clones locales falsos y confirma que Nueva aparece solo al final.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
TMP=$(mktemp -d)
REPO_ROOT="$PWD"
ROOT="$TMP/repo"
mkdir -p "$ROOT/runtime/desarrollo" "$ROOT/runtime/addons" "$ROOT/stacks"
cp -R "$REPO_ROOT/scripts" "$ROOT/"
cp -R "$REPO_ROOT/stacks/odoo" "$ROOT/stacks/odoo"
cp "$REPO_ROOT/runtime/desarrollo/compose.env.example" "$ROOT/runtime/desarrollo/compose.env"
printf 'services: {}\n' > "$ROOT/runtime/desarrollo/compose.yaml"
tar -cf "$TMP/runtime-before.tar" -C "$REPO_ROOT" runtime
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
git init -q
git config user.email test@example.invalid
git config user.name test
git add scripts stacks runtime
git commit -qm base
mkdir -p runtime/addons/.repos runtime/addons/custom/desarrollo

git -c init.defaultBranch=main init -q "$TMP/ee"
git -C "$TMP/ee" config user.email test@example.invalid; git -C "$TMP/ee" config user.name test
mkdir -p "$TMP/ee/ventas"; printf "{'name': 'ventas'}\n" > "$TMP/ee/ventas/__manifest__.py"; git -C "$TMP/ee" add .; git -C "$TMP/ee" commit -qm inicial; git -C "$TMP/ee" tag -a 19.0-ee-2026-09-14 -m inmutable; git -C "$TMP/ee" tag 19.0-ee-2026-09-17
git clone -q "$TMP/ee" runtime/addons/enterprise
git -c init.defaultBranch=main init -q "$TMP/domain"
git -C "$TMP/domain" config user.email test@example.invalid; git -C "$TMP/domain" config user.name test
printf "{'name': 'ventas'}\n" > "$TMP/domain/__manifest__.py"; git -C "$TMP/domain" add .; git -C "$TMP/domain" commit -qm inicial
COMMIT=$(git -C "$TMP/domain" rev-parse HEAD); git clone --bare -q "$TMP/domain" runtime/addons/.repos/ventas.git
mkdir -p runtime/addons/custom/desarrollo/ventas; printf '%s\n' "$COMMIT" > runtime/addons/custom/desarrollo/ventas/.candidate-commit
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
if [ "${BUILD_FAIL:-0}" = 1 ] && [ "$1" = build ]; then exit 1; fi
if [ "$1" = image ] && [ "$2" = inspect ]; then printf 'sha256:build-digest\n'; fi
DOCKER
chmod +x "$TMP/bin/docker"
export ENTORNO=desarrollo ENTERPRISE_TAG=19.0-ee-2026-09-13 PATH="$TMP/bin:$PATH"
printf '%s\n' 'ODOO_EDITION=enterprise' 'TAG=19.0-ee-2026-09-14' >> runtime/desarrollo/compose.env
salida=$(scripts/build-odoo-image.sh 2>&1); codigo=$?
igual "build exitoso" 0 "$codigo"
contiene "registra Nueva con tag inmutable" 'Nueva registrada: local/odoo:19.0-desarrollo-' "$salida"
CONTENIDO_EE="$(scripts/image-state.sh get Nueva)"
contiene "conserva digest" 'sha256:build-digest' "$CONTENIDO_EE"
contiene "registra edición Enterprise" '"edition": "enterprise"' "$CONTENIDO_EE"
contiene "registra tag Enterprise configurado" '"edition_tag": "19.0-ee-2026-09-14"' "$CONTENIDO_EE"
contiene "registra commit Enterprise" '"enterprise_commit": "' "$CONTENIDO_EE"
contiene "registra módulo Enterprise" '"enterprise_modules": ["ventas"]' "$CONTENIDO_EE"
contiene "exporta Enterprise" 'enterprise/ventas/__manifest__.py' "$(find runtime/addons/builds/desarrollo -path '*/enterprise/ventas/__manifest__.py' -print)"
contiene "exporta dominio" 'custom/ventas/__manifest__.py' "$(find runtime/addons/builds/desarrollo -path '*/custom/ventas/__manifest__.py' -print)"

# Fallos de selección Enterprise
# Ningún tag o checkout inválido puede publicar Nueva.
printf '%s\n' 'TAG=' >> runtime/desarrollo/compose.env
rm -f runtime/desarrollo/state/images.json
sale_con "tag Enterprise ausente falla antes del build" 2 scripts/build-odoo-image.sh
printf '%s\n' 'TAG=19.0-ee-2026-09-14' >> runtime/desarrollo/compose.env
rm -f runtime/desarrollo/state/images.json
rm -rf runtime/addons/enterprise
sale_con "checkout Enterprise ausente falla" 1 scripts/build-odoo-image.sh
git clone -q "$TMP/ee" runtime/addons/enterprise
printf '%s\n' 'TAG=19.0-ee-2026-09-16' >> runtime/desarrollo/compose.env
rm -f runtime/desarrollo/state/images.json
sale_con "tag Enterprise inexistente falla" 1 scripts/build-odoo-image.sh
printf '%s\n' 'TAG=19.0-ee-2026-09-17' >> runtime/desarrollo/compose.env
rm -f runtime/desarrollo/state/images.json
sale_con "tag Enterprise liviano falla" 1 scripts/build-odoo-image.sh
printf '%s\n' 'TAG=19.0-ee-2026-09-14' >> runtime/desarrollo/compose.env
touch runtime/addons/enterprise/edicion.local
rm -f runtime/desarrollo/state/images.json
sale_con "checkout Enterprise sucio falla" 1 scripts/build-odoo-image.sh
rm -f runtime/addons/enterprise/edicion.local
igual "los fallos no publican Nueva" 'null' "$(scripts/image-state.sh get Nueva)"

export BUILD_FAIL=1
rm -f runtime/desarrollo/state/images.json
sale_con "build fallido no publica Nueva" 1 scripts/build-odoo-image.sh
igual "estado queda sin Nueva" 'null' "$(scripts/image-state.sh get Nueva)"

# Community con residual Enterprise
# El checkout privado permanece para demostrar que no se copia ni se registra.
export BUILD_FAIL=0
printf '%s\n' 'ODOO_EDITION=community' 'TAG=19.0-ce-2026-09-16' >> runtime/desarrollo/compose.env
rm -f runtime/desarrollo/state/images.json
salida=$(scripts/build-odoo-image.sh 2>&1); codigo=$?
igual "build Community exitoso con residual Enterprise" 0 "$codigo"
contiene "registra Nueva Community" 'Nueva registrada: local/odoo:19.0-desarrollo-' "$salida"
CONTENIDO="$(scripts/image-state.sh get Nueva)"
contiene "registra edición Community" '"edition": "community"' "$CONTENIDO"
contiene "registra tag Community" '"edition_tag": "19.0-ce-2026-09-16"' "$CONTENIDO"
contiene "omite tag Enterprise" '"enterprise_tag": null' "$CONTENIDO"
contiene "omite commit Enterprise" '"enterprise_commit": null' "$CONTENIDO"
contiene "registra inventario Enterprise vacío" '"enterprise_modules": []' "$CONTENIDO"
CE_BUILD="$(find runtime/addons/builds/desarrollo -mindepth 2 -maxdepth 2 -name image.json -type f -print | while IFS= read -r metadata; do grep -q '"edition": "community"' "$metadata" && dirname "$metadata" && break; done)"
igual "Community no exporta código Enterprise" '' "$(find "$CE_BUILD/enterprise" -name __manifest__.py -type f -print)"
no_contiene "Community no registra código Enterprise" 'enterprise/__manifest__.py' "$CONTENIDO"

tar -cf "$TMP/runtime-after.tar" -C "$REPO_ROOT" runtime
igual "el test no modifica runtime preexistente" "0" "$(cmp -s "$TMP/runtime-before.tar" "$TMP/runtime-after.tar"; echo $?)"

resumen
