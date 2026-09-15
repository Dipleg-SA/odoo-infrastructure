#!/usr/bin/env bash
# Contrato del bootstrap de URLs de reportes. No usa Docker real: el stub modela
# la salud de Odoo y la lectura/escritura de ir_config_parameter.

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ROOT="$TMP/checkout"
FAKEBIN="$ROOT/fakebin"
mkdir -p "$ROOT/scripts/lib" "$FAKEBIN"
cp scripts/odoo-report-config.sh "$ROOT/scripts/"
cp scripts/lib/ui.sh scripts/lib/contexto.sh "$ROOT/scripts/lib/"
cp scripts/lib/odoo-report.sh "$ROOT/scripts/lib/"
chmod +x "$ROOT/scripts/odoo-report-config.sh"

mkdir -p "$ROOT/runtime/desarrollo"
cat > "$ROOT/runtime/desarrollo/compose.yaml" <<'EOF'
name: prueba-reportes
services: {}
EOF
cat > "$ROOT/runtime/desarrollo/compose.env" <<'EOF'
COMPOSE_PROJECT_NAME=prueba-reportes
HTTP_PORT=8081
REPORT_URL=http://odoo:8069
RUNTIME_CONFIG_DIR=../../runtime/desarrollo/config
RUNTIME_SECRETS_DIR=../../runtime/desarrollo/secrets
RUNTIME_STATE_DIR=../../runtime/desarrollo/state
EOF

cat > "$ROOT/params" <<'EOF'
report.url|http://old-odoo:8069
web.base.url|http://127.0.0.1:8080
web.base.url.freeze|False
EOF

cat > "$FAKEBIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_CALLS"

[ "${1:-}" = compose ] || exit 1
shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file|-f) shift 2 ;;
    *) break ;;
  esac
done

case "${1:-}" in
  ps)
  printf 'odoo-id\n'
  exit 0
  ;;
  restart) exit 0 ;;
  exec) shift ;;
  *) exit 1 ;;
esac

case "${2:-}" in
  odoo)
    printf '{"status":"pass"}\n'
    ;;
  postgres)
    sql=""
    for arg in "$@"; do
      case "$arg" in
        *"SELECT key, COALESCE"*|*"INSERT INTO ir_config_parameter"*) sql="$arg" ;;
      esac
    done
    if [[ "$sql" != *"SELECT key, COALESCE"* ]]; then
      cat >/dev/null
      cat > "$PARAMS_STATE" <<'PARAMS'
report.url|http://odoo:8069
web.base.url|http://127.0.0.1:8081
web.base.url.freeze|True
PARAMS
    else
      cat "$PARAMS_STATE"
    fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKEBIN/docker"

SALIDA=$(cd "$ROOT" && PATH="$FAKEBIN:$PATH" ENTORNO=desarrollo DOCKER_CALLS="$ROOT/docker-calls" PARAMS_STATE="$ROOT/params" ./scripts/odoo-report-config.sh 2>&1)

titulo "odoo-report-config.sh — URLs separadas y escritura idempotente"
contiene "usa la URL interna" "report.url = http://odoo:8069" "$SALIDA"
contiene "deriva la URL pública de development" "web.base.url = http://127.0.0.1:8081" "$SALIDA"
contiene "congela la URL pública" "web.base.url.freeze = True" "$SALIDA"
contiene "comprueba salud desde Odoo" "exec -T odoo curl -fsS http://odoo:8069/web/health" "$(cat "$ROOT/docker-calls")"
contiene "escribe en Postgres" "exec -T postgres psql" "$(cat "$ROOT/docker-calls")"
contiene "recarga los workers" "reiniciar Odoo para recargar los parámetros" "$SALIDA"

: > "$ROOT/docker-calls"
SALIDA_REPETIDA=$(cd "$ROOT" && PATH="$FAKEBIN:$PATH" ENTORNO=desarrollo DOCKER_CALLS="$ROOT/docker-calls" PARAMS_STATE="$ROOT/params" ./scripts/odoo-report-config.sh 2>&1)
contiene "segunda ejecución conserva la configuración" "URLs de reportes ya configuradas" "$SALIDA_REPETIDA"
no_contiene "segunda ejecución no reinicia Odoo" "reiniciar Odoo para recargar los parámetros" "$SALIDA_REPETIDA"

resumen
