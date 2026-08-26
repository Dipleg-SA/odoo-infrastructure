#!/usr/bin/env bash
# Units de systemd de ESTE checkout. Dueño único de dos cosas: qué units le
# corresponden al stack y con qué nombre quedan instaladas. verify.sh pregunta acá.
set -uo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

# --- Valores por deployment ---
# De .env, como verify.sh: el nombre de las units no puede depender de la shell.

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

VERBO="${1:-}"
ORIGEN="docker/host/systemd"
DESTINO="${SYSTEMD_DIR:-/etc/systemd/system}"

# --- Prefijo del nombre ---
# El proyecto va adelante: las units apuntan a un checkout, no a un stack, y sin
# el prefijo el segundo checkout del host pisa las del primero.

PROYECTO="${COMPOSE_PROJECT_NAME:-}"
if [ -z "$PROYECTO" ]; then
  ui_bad "falta COMPOSE_PROJECT_NAME en .env" "sin él las units no tienen nombre propio" >&2
  exit 2
fi

# --- Qué units corresponden ---
# Se deriva de la composición, como las guardas del Makefile: el stack que trae
# 'backup' respalda y el que trae 'certbot' renueva. Development no trae ninguno.

bases() {
  local servicios
  servicios=$(docker compose --profile cert config --services 2>/dev/null)
  if [ -z "$servicios" ]; then
    ui_bad "no se pudo leer la composición" "revisar COMPOSE_FILE en .env" >&2
    return 1
  fi
  printf '%s\n' "$servicios" | grep -qx backup  && printf 'backup-daily\nbackup-monthly\n'
  printf '%s\n' "$servicios" | grep -qx certbot && printf 'cert-renew\n'
  return 0
}

# --- Nombres instalados ---
# Sin extensión: cada consumidor le pega .timer o .service. La plantilla de aviso
# va aparte porque no es un par service+timer, sino una sola unit instanciable.

units() {
  local lista base
  lista=$(bases) || return 1
  for base in $lista; do printf '%s-%s\n' "$PROYECTO" "$base"; done
}

notify() { printf '%s-notify@\n' "$PROYECTO"; }

# --- Materializar una unit ---
# Los dos reemplazos que la plantilla no puede traer resueltos: la ruta absoluta
# del checkout y el prefijo del OnFailure=, que nombra otra unit de este mismo stack.

instalar_archivo() {
  local origen="$1" destino="$2"
  sed -e "s|CAMBIAR-en-deploy|$PWD|g" \
      -e "s|^OnFailure=|OnFailure=$PROYECTO-|" \
      "$origen" > "$destino" || return $?
  chmod 644 "$destino"
}

# --- Units que dejaron de corresponder ---
# El stack pudo perder una capa desde la última instalación: la unit vieja sigue
# enabled y dispara igual, contra un checkout que ya no la puede atender.

limpiar_sobrantes() {
  local lista="$1" archivo base
  for archivo in "$DESTINO/$PROYECTO-"*.timer; do
    [ -e "$archivo" ] || continue
    base=$(basename "$archivo" .timer); base="${base#"$PROYECTO"-}"
    printf '%s\n' $lista | grep -qx "$base" && continue
    systemctl disable --now "$PROYECTO-$base.timer" >/dev/null 2>&1
    rm -f "$DESTINO/$PROYECTO-$base.timer" "$DESTINO/$PROYECTO-$base.service"
    ui_ok "removida: $PROYECTO-$base.{service,timer} (ya no corresponde a este stack)"
  done
}

install() {
  local lista base
  lista=$(bases) || return 1

  if [ "$(id -u)" -ne 0 ] && [ "$DESTINO" = "/etc/systemd/system" ]; then
    ui_bad "timers-install necesita root" "sudo make timers-install" >&2
    return 2
  fi

  mkdir -p "$DESTINO"
  limpiar_sobrantes "$lista"

  if [ -z "$lista" ]; then
    ui_skip "este stack no lleva units (no respalda ni renueva certificados)"
    return 0
  fi

  for base in $lista; do
    instalar_archivo "$ORIGEN/$base.service" "$DESTINO/$PROYECTO-$base.service" || return $?
    instalar_archivo "$ORIGEN/$base.timer"   "$DESTINO/$PROYECTO-$base.timer"   || return $?
    ui_ok "instalada: $PROYECTO-$base.{service,timer}"
  done

  # Sin la plantilla de aviso, una corrida que falle no le avisa a nadie.
  instalar_archivo "$ORIGEN/notify@.service" "$DESTINO/$PROYECTO-notify@.service" || return $?
  ui_ok "instalada: $PROYECTO-notify@.service"

  systemctl daemon-reload || return $?

  local timers=""
  for base in $lista; do timers="$timers $PROYECTO-$base.timer"; done
  # shellcheck disable=SC2086
  systemctl enable --now $timers || return $?
  ui_ok "activos:$timers"
}

case "$VERBO" in
  install) ui_start "timers-install ($PROYECTO)"; install; ec=$?
           if [ "$ec" -eq 0 ]; then ui_ok "timers-install listo"; else ui_bad "timers-install falló" "exit $ec"; fi
           exit "$ec" ;;
  units)   units ;;
  notify)  notify ;;
  *)       ui_bad "uso: $(basename "$0") install|units|notify" "" >&2; exit 2 ;;
esac
