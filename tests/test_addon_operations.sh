#!/usr/bin/env bash
# Contrato del runner común de operaciones de módulos. No usa Docker real: el
# stub verifica que las tres acciones pasan por odoo shell y que el servicio se
# levanta junto con la configuración posterior de reportes.

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ROOT="$TMP/checkout"
FAKEBIN="$ROOT/fakebin"
mkdir -p "$ROOT/scripts/lib" "$FAKEBIN" "$ROOT/runtime/desarrollo/state"
cp scripts/odoo-module-operation.sh scripts/image-state.sh "$ROOT/scripts/"
cp scripts/lib/ui.sh scripts/lib/contexto.sh "$ROOT/scripts/lib/"
chmod +x "$ROOT/scripts/odoo-module-operation.sh"

cat > "$ROOT/runtime/desarrollo/compose.env" <<'EOF'
COMPOSE_PROJECT_NAME=test-development
HTTP_PORT=8081
ODOO_EDITION=community
TAG=19.0-ce-2026-09-16
EOF
cat > "$ROOT/runtime/desarrollo/compose.yaml" <<'EOF'
services: {}
EOF
cat > "$ROOT/runtime/desarrollo/state/images.json" <<'EOF'
{"Nueva":null,"Actual":{"tag":"local/odoo:actual","digest":"sha256:actual"},"Anterior":null,"validation":null}
EOF

cat > "$FAKEBIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_CALLS"

[ "${1:-}" = compose ] || exit 1

subcomando=""
for argumento in "$@"; do
  case "$argumento" in stop|up|run) subcomando="$argumento"; break ;; esac
done
case "$subcomando" in
  stop|up)
    exit 0
    ;;
  run)
    operation=""
    phase=""
    servicio=""
    shell=0
    no_http=0
    for arg in "$@"; do
      case "$arg" in
        ODOO_OPERATION=*) operation="${arg#*=}" ;;
        ODOO_PHASE=*) phase="${arg#*=}" ;;
        odoo) servicio=odoo ;;
        shell) shell=1 ;;
        --no-http) no_http=1 ;;
      esac
    done
    if [ "$servicio" != odoo ] || [ "$shell" -ne 1 ] || [ "$no_http" -ne 1 ]; then
      printf 'invocación inválida: servicio=%s shell=%s no_http=%s\n' \
        "$servicio" "$shell" "$no_http"
      exit 19
    fi
    cat >/dev/null
  printf 'API operation=%s phase=%s\n' "$operation" "$phase"
  if [ "${FAIL_RUN:-}" = 1 ]; then
    exit 17
  fi
  ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$FAKEBIN/docker"

cat > "$FAKEBIN/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'make %s\n' "$*" >> "$MAKE_CALLS"
EOF
chmod +x "$FAKEBIN/make"

run_operation() {
  local action="$1" modules="$2" confirm="${3:-}"
  (cd "$ROOT" && PATH="$FAKEBIN:$PATH" \
    ENTORNO=desarrollo \
    DOCKER_CALLS="$ROOT/docker-calls" MAKE_CALLS="$ROOT/make-calls" \
    MODULES="$modules" CONFIRM="$confirm" \
    ./scripts/odoo-module-operation.sh "$action" 2>&1)
}

SALIDA_INSTALL=$(run_operation install dipl_doc_sale)
SALIDA_UPDATE=$(run_operation update dipl_doc_sale)
SALIDA_UNINSTALL=$(run_operation uninstall dipl_doc_sale desinstalar)

set +e
SALIDA_FAILURE=$(cd "$ROOT" && PATH="$FAKEBIN:$PATH" \
  ENTORNO=desarrollo \
  DOCKER_CALLS="$ROOT/docker-calls" MAKE_CALLS="$ROOT/make-calls" \
  MODULES="dipl_doc_sale" FAIL_RUN=1 \
  ./scripts/odoo-module-operation.sh install 2>&1)
ESTADO_FAILURE=$?

titulo "odoo-module-operation.sh — API común para addons"
contiene "instala mediante la API" "API operation=install phase=apply" "$SALIDA_INSTALL"
contiene "actualiza mediante la API" "API operation=update phase=apply" "$SALIDA_UPDATE"
contiene "previsualiza la desinstalación" "API operation=uninstall phase=preflight" "$SALIDA_UNINSTALL"
contiene "desinstala mediante la API" "API operation=uninstall phase=apply" "$SALIDA_UNINSTALL"
contiene "levanta Odoo después de operar" "make odoo-report-config" "$(cat "$ROOT/make-calls")"
contiene "usa el one-off común" "run --rm --name odoo-oneoff" "$(cat "$ROOT/docker-calls")"
sale_con "conserva el error del one-off" 17 bash -c "exit $ESTADO_FAILURE"
contiene "levanta Odoo aunque falle la API" "up -d odoo" "$(cat "$ROOT/docker-calls")"

resumen
