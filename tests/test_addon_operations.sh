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
cp scripts/odoo-module-operation.sh "$ROOT/scripts/"
cp scripts/lib/ui.sh scripts/lib/contexto.sh scripts/lib/candidate-lock.sh "$ROOT/scripts/lib/"
chmod +x "$ROOT/scripts/odoo-module-operation.sh"

cat > "$ROOT/scripts/addons-runtime.sh" <<'EOF'
#!/usr/bin/env bash
printf 'addons-runtime %s\n' "$*" >> "$PREFLIGHT_CALLS"
exit "${PREFLIGHT_FAIL:-0}"
EOF
cat > "$ROOT/scripts/odoo-lifecycle.sh" <<'EOF'
#!/usr/bin/env bash
printf 'odoo-lifecycle %s\n' "$*" >> "$LIFECYCLE_CALLS"
exit 0
EOF
chmod +x "$ROOT/scripts/addons-runtime.sh" "$ROOT/scripts/odoo-lifecycle.sh"

cat > "$ROOT/runtime/desarrollo/compose.env" <<'EOF'
COMPOSE_PROJECT_NAME=test-development
HTTP_PORT=8081
ODOO_EDITION=community
TAG=19.0-ce-2026-09-16
ODOO_IMAGE=local/odoo:19.0-desarrollo-20260917T183719Z-fa588059f4932d2f
EOF
cat > "$ROOT/runtime/desarrollo/compose.yaml" <<'EOF'
services: {}
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
    PREFLIGHT_CALLS="$ROOT/preflight-calls" LIFECYCLE_CALLS="$ROOT/lifecycle-calls" \
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
  PREFLIGHT_CALLS="$ROOT/preflight-calls" LIFECYCLE_CALLS="$ROOT/lifecycle-calls" \
  MODULES="dipl_doc_sale" FAIL_RUN=1 \
  ./scripts/odoo-module-operation.sh install 2>&1)
ESTADO_FAILURE=$?

titulo "odoo-module-operation.sh — API común para addons"
contiene "instala mediante la API" "API operation=install phase=apply" "$SALIDA_INSTALL"
contiene "actualiza mediante la API" "API operation=update phase=apply" "$SALIDA_UPDATE"
contiene "previsualiza la desinstalación" "API operation=uninstall phase=preflight" "$SALIDA_UNINSTALL"
contiene "desinstala mediante la API" "API operation=uninstall phase=apply" "$SALIDA_UNINSTALL"
contiene "valida la imagen Odoo seleccionada" "make require-odoo-image" "$(cat "$ROOT/make-calls")"
contiene "levanta Odoo después de operar" "make odoo-report-config" "$(cat "$ROOT/make-calls")"
contiene "ejecuta preflight antes de operar" "addons-runtime preflight" "$(cat "$ROOT/preflight-calls")"
contiene "recrea Odoo mediante el lifecycle" "odoo-lifecycle up" "$(cat "$ROOT/lifecycle-calls")"
contiene "usa el one-off del proyecto y entorno" \
  "run --rm --name test-development-desarrollo-odoo-oneoff" "$(cat "$ROOT/docker-calls")"
sale_con "conserva el error del one-off" 17 bash -c "exit $ESTADO_FAILURE"
contiene "recrea Odoo aunque falle la API" "odoo-lifecycle up" "$(cat "$ROOT/lifecycle-calls")"

# Preflight incompatible
# Una base o huella distinta debe cortar antes de stop y del one-off.
LLAMADAS_ANTES=$(wc -l < "$ROOT/docker-calls" | tr -d ' ')
sale_con "una imagen incompatible bloquea la operación" 1 env PATH="$FAKEBIN:$PATH" \
  ENTORNO=desarrollo DOCKER_CALLS="$ROOT/docker-calls" MAKE_CALLS="$ROOT/make-calls" \
  PREFLIGHT_CALLS="$ROOT/preflight-calls" LIFECYCLE_CALLS="$ROOT/lifecycle-calls" \
  PREFLIGHT_FAIL=1 MODULES=dipl_doc_sale "$ROOT/scripts/odoo-module-operation.sh" update
igual "el preflight incompatible falla antes de Compose" "$LLAMADAS_ANTES" \
  "$(wc -l < "$ROOT/docker-calls" | tr -d ' ')"
igual "la operación usa el lock compartido del entorno" "0" \
  "$([ -f "$ROOT/runtime/control/state/locks/environments/desarrollo.lock" ]; echo $?)"

# Contención funcional
# Una segunda operación no alcanza Compose hasta que se libera el lock del entorno.
LOCK_PATH="$ROOT/runtime/control/state/locks/environments/desarrollo.lock"
HELD="$ROOT/lock-held"
RELEASE="$ROOT/lock-release"
python3 - "$LOCK_PATH" "$HELD" "$RELEASE" <<'PY' &
import fcntl, os, pathlib, sys, time
lock, held, release = map(pathlib.Path, sys.argv[1:])
lock.parent.mkdir(parents=True, exist_ok=True)
with lock.open("a+b") as stream:
    fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
    held.write_text("held")
    while not release.exists():
        time.sleep(0.01)
PY
HOLDER_PID=$!
for _ in $(seq 1 200); do [ -f "$HELD" ] && break; sleep 0.01; done
LLAMADAS_BLOQUEADAS=$(wc -l < "$ROOT/docker-calls" | tr -d ' ')
run_operation update dipl_doc_sale > "$ROOT/concurrent-output" 2>&1 &
OPERATION_PID=$!
sleep 0.1
igual "la operación concurrente espera el lock" "$LLAMADAS_BLOQUEADAS" \
  "$(wc -l < "$ROOT/docker-calls" | tr -d ' ')"
touch "$RELEASE"
wait "$HOLDER_PID"
wait "$OPERATION_PID"
igual "la operación continúa después de liberar el lock" "0" \
  "$([ "$(wc -l < "$ROOT/docker-calls" | tr -d ' ')" -gt "$LLAMADAS_BLOQUEADAS" ]; echo $?)"

resumen
