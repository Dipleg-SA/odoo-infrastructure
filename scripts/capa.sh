#!/usr/bin/env bash
# Despachador de ciclo de vida por capa: up/down/restart/logs/ps/verify/nuke.
# Único lugar que sabe qué servicios y volúmenes son de cada capa; el Makefile
# solo lo invoca. Resuelve contra la composición real, nunca contra una lista fija.
set -uo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

CAPA="${1:-}"; VERBO="${2:-}"
[ -n "$CAPA" ] && [ -n "$VERBO" ] || { ui_bad "uso: $(basename "$0") <capa> <verbo>" ""; exit 2; }

# --- Compose que declara cada capa ---
# De ahí, y no de una lista aparte, salen los servicios (servicios_de) y volúmenes (volumenes_de_capa) dueños de la capa.

compose_de() {
  case "$1" in
    edge)          echo "compose.dns.yaml compose.proxy.yaml compose.edge.yaml" ;;
    db)            echo "compose.db.yaml" ;;
    odoo)          echo "compose.odoo.yaml" ;;
    backups)       echo "compose.backups.yaml" ;;
    observability) echo "compose.observability.yaml" ;;
  esac
}

# --- Servicios canónicos por capa ---
# Deriva de compose_de(): lee el bloque 'services:' del/los compose.*.yaml de la capa.

servicios_de() {
  local capa="$1" f
  for f in $(compose_de "$capa"); do
    [ -f "$f" ] || continue
    awk '
      /^services:/ {enbloque=1; next}
      enbloque && /^[a-zA-Z]/ {enbloque=0}
      enbloque && /^  [a-zA-Z0-9_.-]+:/ {sub(/:.*/,""); sub(/^  /,""); print}
    ' "$f"
  done
}

# --- Nuke global ---
# 'all' es un pseudo-capa que solo admite nuke: todo el stack, más lo transversal (addons/, state/).

nuke_global() {
  echo "Se va a borrar TODO: containers, volúmenes e imágenes del stack completo,"
  echo "más addons/.repos, los árboles clonados bajo addons/ y state/*."
  echo "secrets/ y .env NO se tocan — son credenciales de terceros, no derivables de nada."
  ui_confirm_nuke || return 1

  docker compose down --rmi all -v --remove-orphans || return $?
  rm -rf addons/.repos addons/enterprise/* addons/custom-addons/* addons/oca/* addons/third-party/*
  rm -rf state/textfile/* state/meta/*
}

if [ "$CAPA" = "all" ]; then
  [ "$VERBO" = "nuke" ] || { ui_bad "la capa 'all' solo admite nuke" "usá 'make nuke', o 'make <capa>-$VERBO' para una capa puntual"; exit 2; }
  ui_start "nuke"
  if nuke_global; then ui_ok "nuke listo"
  else ec=$?; ui_bad "nuke falló o se canceló" "exit $ec"; exit "$ec"; fi
  exit 0
fi

# host no tiene contenedores — son chequeos de SO, no hay ciclo de vida que ofrecerle.
if [ "$CAPA" = "host" ]; then
  [ "$VERBO" = "verify" ] || { ui_bad "host no tiene ciclo de vida de contenedores" "usá 'make host-verify'"; exit 2; }
  exec scripts/verify.sh host
fi

# verify es scripts/verify.sh sin más: dueño único de qué se chequea, no se reimplementa acá.
if [ "$VERBO" = "verify" ]; then
  exec scripts/verify.sh "$CAPA"
fi

canon="$(servicios_de "$CAPA")"
[ -n "$canon" ] || { ui_bad "capa desconocida" "$CAPA"; exit 2; }

# --- Presencia real ---
# Qué subconjunto de la lista canónica declara ESTE stack — staging no trae dnsmasq,
# dev no trae backups/observability, y ninguna lista fija sabe eso de antemano.

presentes=$(docker compose --profile cert --profile restore config --services 2>/dev/null | grep -Fxf <(printf '%s\n' $canon) | tr '\n' ' ')
presentes="${presentes% }"

if [ -z "$presentes" ]; then
  ui_skip "la capa $CAPA no está en este stack (revisar COMPOSE_FILE en .env)"
  exit 0
fi

# --- Volúmenes dueños de la capa ---
# Lee 'volumes:' de compose_de(); un servicio que solo MONTA un volumen ajeno no lo vuelve dueño.

volumenes_de_capa() {
  local capa="$1" f
  for f in $(compose_de "$capa"); do
    [ -f "$f" ] || continue
    awk '
      /^volumes:/ {enbloque=1; next}
      enbloque && /^[a-zA-Z]/ {enbloque=0}
      enbloque && /^  [a-zA-Z0-9_.-]+:/ {sub(/:.*/,""); sub(/^  /,""); print}
    ' "$f"
  done
}

nuke_capa() {
  local vols imgs
  vols=$(volumenes_de_capa "$CAPA" | tr '\n' ' '); vols="${vols% }"
  echo "Se van a borrar de la capa $CAPA: containers ($presentes), imágenes, y volúmenes (${vols:-ninguno})."
  echo "addons/ y state/ NO se tocan acá — eso es 'make nuke' (global), no un nuke por capa."
  ui_confirm_nuke || return 1

  imgs=$(docker compose images -q $presentes 2>/dev/null | sort -u | tr '\n' ' '); imgs="${imgs% }"

  docker compose rm -sf $presentes || return $?
  if [ -n "$vols" ]; then docker volume rm -f $vols || return $?; fi
  if [ -n "$imgs" ]; then docker rmi -f $imgs || return $?; fi
  return 0
}

case "$VERBO" in
  up)      ui_run "$CAPA-up" docker compose up -d $presentes ;;
  down)    ui_run "$CAPA-down" docker compose rm -sf $presentes ;;
  restart) ui_run "$CAPA-restart" docker compose restart $presentes ;;
  ps)      ui_run "$CAPA-ps" docker compose ps $presentes ;;
  logs)
    ui_start "$CAPA-logs: siguiendo $presentes (Ctrl-C para salir)"
    exec docker compose logs -f $presentes
    ;;
  nuke)
    ui_start "$CAPA-nuke"
    if nuke_capa; then ui_ok "$CAPA-nuke listo"
    else ec=$?; ui_bad "$CAPA-nuke falló o se canceló" "exit $ec"; exit "$ec"; fi
    ;;
  *) ui_bad "verbo desconocido" "$VERBO"; exit 2 ;;
esac
