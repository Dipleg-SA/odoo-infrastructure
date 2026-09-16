#!/usr/bin/env bash
# Contrato de fotografía Odoo
# Construye con clones locales falsos y confirma que Nueva aparece solo al final.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
TMP=$(mktemp -d)
CREADO_ENV=0
trap 'rm -rf "$TMP" runtime/addons/enterprise runtime/addons/.repos runtime/addons/custom/desarrollo runtime/addons/builds/desarrollo runtime/desarrollo/state/images.json; [ "$CREADO_ENV" -eq 0 ] || rm -f runtime/desarrollo/compose.env' EXIT
if [ ! -f runtime/desarrollo/compose.env ]; then cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env; CREADO_ENV=1; fi
rm -rf runtime/addons/enterprise runtime/addons/.repos runtime/addons/custom/desarrollo runtime/addons/builds/desarrollo runtime/desarrollo/state/images.json
mkdir -p runtime/addons/.repos runtime/addons/custom/desarrollo

git -c init.defaultBranch=main init -q "$TMP/ee"
git -C "$TMP/ee" config user.email test@example.invalid; git -C "$TMP/ee" config user.name test
echo "enterprise" > "$TMP/ee/__manifest__.py"; git -C "$TMP/ee" add .; git -C "$TMP/ee" commit -qm inicial; git -C "$TMP/ee" tag -a 19.0-ee-2026-09-14 -m inmutable
git clone -q "$TMP/ee" runtime/addons/enterprise
git -c init.defaultBranch=main init -q "$TMP/domain"
git -C "$TMP/domain" config user.email test@example.invalid; git -C "$TMP/domain" config user.name test
echo "domain" > "$TMP/domain/__manifest__.py"; git -C "$TMP/domain" add .; git -C "$TMP/domain" commit -qm inicial
COMMIT=$(git -C "$TMP/domain" rev-parse HEAD); git clone --bare -q "$TMP/domain" runtime/addons/.repos/ventas.git
mkdir -p runtime/addons/custom/desarrollo/ventas; printf '%s\n' "$COMMIT" > runtime/addons/custom/desarrollo/ventas/.candidate-commit
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
if [ "${BUILD_FAIL:-0}" = 1 ] && [ "$1" = build ]; then exit 1; fi
if [ "$1" = image ] && [ "$2" = inspect ]; then printf 'sha256:build-digest\n'; fi
DOCKER
chmod +x "$TMP/bin/docker"
export ENTORNO=desarrollo ENTERPRISE_TAG=19.0-ee-2026-09-14 PATH="$TMP/bin:$PATH"
printf '%s\n' 'ODOO_EDITION=enterprise' 'TAG=19.0-ee-2026-09-14' >> runtime/desarrollo/compose.env
salida=$(scripts/build-odoo-image.sh 2>&1); codigo=$?
igual "build exitoso" 0 "$codigo"
contiene "registra Nueva con tag inmutable" 'Nueva registrada: local/odoo:19.0-desarrollo-' "$salida"
contiene "conserva digest" 'sha256:build-digest' "$(scripts/image-state.sh get Nueva)"
contiene "exporta Enterprise" 'enterprise/__manifest__.py' "$(find runtime/addons/builds/desarrollo -path '*/enterprise/__manifest__.py' -print)"
contiene "exporta dominio" 'custom/ventas/__manifest__.py' "$(find runtime/addons/builds/desarrollo -path '*/custom/ventas/__manifest__.py' -print)"
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
CE_BUILD="$(find runtime/addons/builds/desarrollo -mindepth 1 -maxdepth 1 -type d -print | sort | tail -1)"
igual "Community no exporta código Enterprise" '' "$(find "$CE_BUILD/enterprise" -name __manifest__.py -type f -print)"
no_contiene "Community no registra código Enterprise" 'enterprise/__manifest__.py' "$CONTENIDO"

resumen
