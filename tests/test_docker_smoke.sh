#!/usr/bin/env bash
# Smoke real de Docker
# Construye Odoo y valida las configuraciones efectivas solo cuando se solicita explícitamente.
set -euo pipefail

cd "$(dirname "$0")/.."

# Opt-in
# make test no levanta Docker ni necesita red; este archivo solo corre con DOCKER_SMOKE=1.
if [ "${DOCKER_SMOKE:-0}" != 1 ]; then
  printf 'smoke Docker omitido — usar DOCKER_SMOKE=1 make test-smoke\n'
  exit 0
fi

command -v docker >/dev/null 2>&1 || {
  printf 'smoke Docker: falta el cliente docker\n' >&2
  exit 2
}
docker info >/dev/null 2>&1 || {
  printf 'smoke Docker: el daemon no responde\n' >&2
  exit 2
}

TMP=$(mktemp -d)
ODOO_IMAGE="local/odoo:19.0-desarrollo-20990101T010101Z-a1b2c3d4e5f60789"
GRAFANA_CONTAINER="odoo-smoke-grafana-$$"
trap 'docker rm -f "$GRAFANA_CONTAINER" >/dev/null 2>&1 || true; docker image rm "$ODOO_IMAGE" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

# Selector único en Compose
# La composición mínima confirma la interpolación exacta que usa el runtime.
printf 'ODOO_IMAGE=%s\n' "$ODOO_IMAGE" > "$TMP/compose.env"
cat > "$TMP/compose.yaml" <<'EOF'
services:
  odoo:
    image: ${ODOO_IMAGE:?falta ODOO_IMAGE}
EOF
docker compose --env-file "$TMP/compose.env" -f "$TMP/compose.yaml" config \
  | grep -q "image: $ODOO_IMAGE"
! grep -q 'images\.json' tests/test_docker_smoke.sh

# Contexto real de Odoo
# El contexto temporal contiene solo dependencias y entrypoint, nunca código de addons.
mkdir -p "$TMP/odoo/enterprise" "$TMP/odoo/custom"
mkdir -p "$TMP/odoo/requirements.sources"
cp stacks/odoo/image/Dockerfile stacks/odoo/image/entrypoint.sh "$TMP/odoo/"
: > "$TMP/odoo/requirements.lock.txt"
docker build --pull --tag "$ODOO_IMAGE" "$TMP/odoo"
docker run --rm --entrypoint /bin/sh "$ODOO_IMAGE" -c \
  'test -x /usr/local/bin/odoo-entrypoint.sh && test ! -e /opt/odoo/enterprise && test ! -e /opt/odoo/custom && test ! -e /tmp/requirements.txt && test ! -e /tmp/wheels && ! command -v swig >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1'

# Addons montados
# El contenedor descubre custom, rechaza escrituras y Community excluye Enterprise.
mkdir -p "$TMP/runtime-addons/custom/ventas" "$TMP/runtime-addons/enterprise/ventas_enterprise" \
  "$TMP/odoo-secrets"
touch "$TMP/runtime-addons/custom/ventas/__manifest__.py" \
  "$TMP/runtime-addons/enterprise/ventas_enterprise/__manifest__.py"
printf '%040d\n' 1 > "$TMP/runtime-addons/custom/ventas/.candidate-commit"
printf '%040d\n' 2 > "$TMP/runtime-addons/custom/ventas/.candidate-tree"
printf 'admin\n' > "$TMP/odoo-secrets/odoo_admin_password"
printf 'postgres\n' > "$TMP/odoo-secrets/postgres_password"
: > "$TMP/odoo-secrets/zeptomail_smtp_password"
chmod 644 "$TMP/odoo-secrets"/*
cat > "$TMP/odoo-stub" <<'EOF'
#!/usr/bin/env bash
grep -q '/opt/odoo/custom/ventas' /tmp/odoo-runtime.conf
! grep -q '/opt/odoo/enterprise' /tmp/odoo-runtime.conf
EOF
chmod 755 "$TMP/odoo-stub"
docker run --rm \
  -e ENTORNO=desarrollo \
  -e TAG=19.0-ce-2099-01-01 \
  -e ODOO_EDITION=community \
  -e ODOO_COMMUNITY_ADDONS=/usr/lib/python3/dist-packages/odoo/addons \
  -v "$TMP/runtime-addons/custom:/opt/odoo/custom:ro" \
  -v "$TMP/runtime-addons/enterprise:/opt/odoo/enterprise:ro" \
  -v "$TMP/odoo-secrets:/run/secrets:ro" \
  -v "$TMP/odoo-stub:/usr/local/bin/odoo:ro" \
  "$ODOO_IMAGE" --stop-after-init
docker run --rm --entrypoint /bin/sh \
  -v "$TMP/runtime-addons/custom:/opt/odoo/custom:ro" \
  -v "$TMP/runtime-addons/enterprise:/opt/odoo/enterprise:ro" \
  "$ODOO_IMAGE" -c \
  'test -f /opt/odoo/custom/ventas/__manifest__.py && test -f /opt/odoo/enterprise/ventas_enterprise/__manifest__.py && ! touch /opt/odoo/custom/escritura && ! touch /opt/odoo/enterprise/escritura'

# Nginx
# El hostname y el certificado se materializan en un árbol descartable antes de validar nginx -t.
mkdir -p "$TMP/nginx/conf.d" "$TMP/nginx/letsencrypt/live/odoo.example.test"
cp stacks/nginx/config/00-http.conf.example "$TMP/nginx/conf.d/00-http.conf"
cp stacks/nginx/config/odoo.locations.example "$TMP/nginx/conf.d/odoo.locations"
cp \
  stacks/nginx/config/addons-webhook.locations "$TMP/nginx/conf.d/"
sed 's/TU_DOMINIO/odoo.example.test/g' stacks/nginx/config/server-tls.conf.example \
  > "$TMP/nginx/conf.d/server-tls.conf"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "$TMP/nginx/letsencrypt/live/odoo.example.test/privkey.pem" \
  -out "$TMP/nginx/letsencrypt/live/odoo.example.test/fullchain.pem" \
  -subj '/CN=odoo.example.test' >/dev/null 2>&1
docker run --rm \
  -v "$TMP/nginx/conf.d:/etc/nginx/conf.d:ro" \
  -v "$TMP/nginx/letsencrypt:/etc/letsencrypt:ro" \
  nginx:1.31.3-alpine nginx -t

# Alloy
# La validación usa el binario real de la imagen y el archivo versionado montado como solo lectura.
docker run --rm \
  -v "$PWD/stacks/alloy/config/config.alloy:/etc/alloy/config.alloy:ro" \
  --entrypoint alloy grafana/alloy:v1.18.1 validate /etc/alloy/config.alloy

# Prometheus
# promtool comprueba la estructura efectiva de scrape_configs y sus campos requeridos.
docker run --rm \
  -v "$PWD/stacks/prometheus/config/prometheus.yaml:/etc/prometheus/prometheus.yml:ro" \
  --entrypoint promtool prom/prometheus:v3.13.2 check config /etc/prometheus/prometheus.yml

# Loki
# El propio proceso de Loki valida esquema, almacenamiento y retención sin iniciar un servicio persistente.
docker run --rm \
  -v "$PWD/stacks/loki/config/loki.yaml:/etc/loki/config.yaml:ro" \
  grafana/loki:3.7.6 -verify-config -config.file=/etc/loki/config.yaml

# Grafana
# Un arranque acotado confirma que el ini, los secrets y los paths de provisioning son utilizables.
mkdir -p "$TMP/grafana/secrets"
printf 'admin-smoke\n' > "$TMP/grafana/secrets/grafana_admin_password"
printf 'smtp-smoke\n' > "$TMP/grafana/secrets/zeptomail_smtp_password"
chmod 644 "$TMP/grafana/secrets"/*
cp stacks/grafana/config/grafana.ini "$TMP/grafana/grafana.ini"
docker run -d --name "$GRAFANA_CONTAINER" --network none \
  -v "$TMP/grafana/grafana.ini:/etc/grafana/grafana.ini:ro" \
  -v "$TMP/grafana/secrets:/run/secrets:ro" \
  --entrypoint grafana grafana/grafana:13.1.3 \
  server --config=/etc/grafana/grafana.ini --homepath=/usr/share/grafana >/dev/null
sleep 3
estado=$(docker inspect -f '{{.State.Status}}' "$GRAFANA_CONTAINER")
if [ "$estado" != running ]; then
  docker logs "$GRAFANA_CONTAINER" >&2 || true
  printf 'smoke Grafana: el proceso terminó en estado %s\n' "$estado" >&2
  exit 1
fi
docker rm -f "$GRAFANA_CONTAINER" >/dev/null

printf 'smoke Docker listo — Odoo y cinco configuraciones efectivas validadas\n'
