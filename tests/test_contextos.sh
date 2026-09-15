#!/usr/bin/env bash
# Prueba selector, carga aislada y despacho de Compose con un checkout temporal.
# El stub registra argumentos sin contactar un daemon.

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
STUB_DIR="$TMP/stub"
ROOT="$TMP/repo"
mkdir -p "$STUB_DIR" "$ROOT/scripts/lib"
ROOT="$(cd "$ROOT" && pwd -P)"
export STUB_DIR
PATH="$REPO_ROOT/tests/stubs:$PATH"
export PATH
trap 'rm -rf "$TMP"' EXIT
cp scripts/lib/contexto.sh "$ROOT/scripts/lib/contexto.sh"
chmod +x "$ROOT/scripts/lib/contexto.sh"

# Checkout de prueba
# Cada runtime tiene valores distintos para detectar cargas cruzadas.
for entorno in desarrollo staging produccion; do
  mkdir -p "$ROOT/runtime/$entorno"
  cat > "$ROOT/runtime/$entorno/compose.yaml" <<EOF
name: prueba-$entorno
services: {}
EOF
  cat > "$ROOT/runtime/$entorno/compose.env" <<EOF
COMPOSE_PROJECT_NAME=prueba-$entorno
MARCADOR_ENTORNO=$entorno
COMPOSE_PROFILES=lan
RUNTIME_CONFIG_DIR=esta-ruta-debe-ser-derivada
EOF
done
mkdir -p "$ROOT/stacks/odoo/image"
printf 'FROM odoo:19.0\n' > "$ROOT/stacks/odoo/image/Dockerfile"

# Limpieza de invocaciones
# Cada aserción observa solo la llamada que acaba de ejecutar.
reset_stub() { rm -f "$STUB_DIR/llamadas" "$STUB_DIR/config" "$STUB_DIR/salida"; }

# Selector obligatorio
# La ausencia y los valores desconocidos deben fallar antes de invocar Docker.
sin_entorno() {
  (cd "$ROOT"; unset ENTORNO; . scripts/lib/contexto.sh; contexto_compose config)
}

entorno_invalido() {
  (cd "$ROOT"; ENTORNO=qa; export ENTORNO; . scripts/lib/contexto.sh; contexto_compose config)
}

reset_stub
sale_con "sin ENTORNO falla con código 2" 2 sin_entorno
igual "sin ENTORNO no invoca Docker" "0" "$([ ! -e "$STUB_DIR/llamadas" ] && echo 0 || echo 1)"
sale_con "ENTORNO desconocido falla con código 2" 2 entorno_invalido
igual "ENTORNO desconocido no invoca Docker" "0" "$([ ! -e "$STUB_DIR/llamadas" ] && echo 0 || echo 1)"

# Aislamiento y despacho
# Cada llamada usa solo el compose.env y compose.yaml del entorno seleccionado.
for entorno in desarrollo staging produccion; do
  reset_stub
  unset COMPOSE_PROJECT_NAME MARCADOR_ENTORNO
  ENTORNO="$entorno"
  export ENTORNO
  . "$ROOT/scripts/lib/contexto.sh"
  codigo=0
  contexto_iniciar || codigo=$?
  igual "$entorno carga su composición" "0" "$codigo"
  igual "$entorno carga su identidad" "prueba-$entorno" "$COMPOSE_PROJECT_NAME"
  igual "$entorno carga solo su marcador" "$entorno" "$MARCADOR_ENTORNO"
  igual "$entorno deriva su ruta privada" "$ROOT/runtime/$entorno/config" "$RUNTIME_CONFIG_DIR"
  igual "$entorno deriva la línea de Odoo" "19.0" "$(contexto_odoo_version)"
  reset_stub
  sale_con "$entorno delega a Compose" 0 contexto_compose config --services
  llamada=$(cat "$STUB_DIR/llamadas")
  contiene "$entorno pasa su compose.env" "--env-file $ROOT/runtime/$entorno/compose.env" "$llamada"
  contiene "$entorno pasa su compose.yaml" "-f $ROOT/runtime/$entorno/compose.yaml" "$llamada"
  case "$entorno" in
    desarrollo) otros="staging produccion" ;;
    staging) otros="desarrollo produccion" ;;
    produccion) otros="desarrollo staging" ;;
  esac
  for otro in $otros; do
    no_contiene "$entorno no carga $otro" "$ROOT/runtime/$otro/compose.env" "$llamada"
  done
  docker() { printf '%s' "${COMPOSE_PROFILES:-}" > "$STUB_DIR/perfiles"; }
  sale_con "$entorno agrega perfiles preservando los existentes" 0 contexto_compose_perfiles restore config --services
  igual "$entorno combina el perfil adicional" "restore,lan" "$(cat "$STUB_DIR/perfiles")"
  unset -f docker
done

# Validación de línea de comandos
# Make puede rechazar un entorno incompleto antes de ejecutar sus recetas.
reset_stub
sale_con "CLI valida el contexto sin llamar a Docker" 0 env ENTORNO=desarrollo bash "$ROOT/scripts/lib/contexto.sh" validar
igual "validar no invoca Docker" "0" "$([ ! -e "$STUB_DIR/llamadas" ] && echo 0 || echo 1)"
sale_con "CLI exige ENTORNO" 2 env -u ENTORNO bash "$ROOT/scripts/lib/contexto.sh" validar

# Archivo privado ausente
# Un runtime sin compose.env no debe caer en otro archivo ni llegar a Docker.
rm "$ROOT/runtime/staging/compose.env"
reset_stub
sin_archivo_env() {
  (cd "$ROOT"; ENTORNO=staging; export ENTORNO; . scripts/lib/contexto.sh; contexto_compose config)
}
sale_con "sin compose.env falla con código 2" 2 sin_archivo_env
igual "sin compose.env no invoca Docker" "0" "$([ ! -e "$STUB_DIR/llamadas" ] && echo 0 || echo 1)"

resumen
