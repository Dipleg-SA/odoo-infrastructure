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

# --- Bloque de nivel superior ---
# Nombres bajo una clave YAML de nivel superior ('services:' o 'volumes:') de un compose.

bloque_yaml() {
  local clave="$1" f; shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    awk -v clave="$clave:" '
      $0==clave {enbloque=1; next}
      enbloque && /^[a-zA-Z]/ {enbloque=0}
      enbloque && /^  [a-zA-Z0-9_.-]+:/ {sub(/:.*/,""); sub(/^  /,""); print}
    ' "$f"
  done
}

# --- Servicios canónicos por capa ---
# Deriva de compose_de(): lee el bloque 'services:' del/los compose.*.yaml de la capa.

servicios_de() { bloque_yaml services $(compose_de "$1"); }

# --- Servicios de este stack ---
# Resuelve la composición real una sola vez y la cachea: el costo es el mismo para todas las capas.

cargar_servicios_stack() {
  [ -n "${SERVICIOS_STACK+x}" ] && return 0
  SERVICIOS_STACK=$(docker compose --profile cert --profile restore config --services 2>/dev/null)
}

# --- Presencia real ---
# Qué subconjunto de la lista canónica declara ESTE stack — staging no trae dnsmasq, dev no trae backups.

presentes_de() {
  local p
  p=$(printf '%s\n' "$SERVICIOS_STACK" | grep -Fxf <(printf '%s\n' $1) | tr '\n' ' ')
  printf '%s' "${p% }"
}

# --- Capas con contenedores ---
# host no entra: son chequeos de SO, sin ciclo de vida de Docker que listar.

CAPAS="edge db odoo backups observability"

# --- ps agrupado ---
# Un título por capa (mismo estilo que 'make help') y su tabla debajo; los servicios sin capa van al final.

ps_todas() {
  local capa canon presentes otros cubiertos="" ec=0
  cargar_servicios_stack
  [ -n "$SERVICIOS_STACK" ] || { ui_bad "ps falló" "no se pudo resolver la composición (¿docker corriendo? ¿COMPOSE_FILE en .env?)"; return 1; }

  for capa in $CAPAS; do
    canon="$(servicios_de "$capa")"
    presentes="$(presentes_de "$canon")"
    [ -n "$presentes" ] || continue
    cubiertos="$cubiertos $presentes"
    ui_title "$capa"
    docker compose ps $presentes --format "table {{.Name}}\t{{.Service}}\t{{.Status}}" | ui_color_status || ec=$?
  done

  # Lo que no es de ninguna capa (restore-*, bajo profiles) igual se lista: 'make ps' es el stack entero.
  otros=$(printf '%s\n' "$SERVICIOS_STACK" | grep -Fxvf <(printf '%s\n' $cubiertos) | tr '\n' ' ')
  otros="${otros% }"
  [ -n "$otros" ] || return "$ec"

  ui_title "otros"
  docker compose --profile cert --profile restore ps $otros --format "table {{.Name}}\t{{.Service}}\t{{.Status}}" | ui_color_status || ec=$?
  return "$ec"
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
  case "$VERBO" in
    ps)
      ps_todas || exit $?
      ;;
    nuke)
      ui_start "nuke"
      if nuke_global; then ui_ok "nuke listo"
      else ec=$?; ui_bad "nuke falló o se canceló" "exit $ec"; exit "$ec"; fi
      ;;
    *)
      ui_bad "la capa 'all' solo admite ps o nuke" "usá 'make nuke', 'make ps', o 'make <capa>-$VERBO' para una capa puntual"
      exit 2
      ;;
  esac
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

cargar_servicios_stack
presentes="$(presentes_de "$canon")"

if [ -z "$presentes" ]; then
  ui_skip "la capa $CAPA no está en este stack (revisar COMPOSE_FILE en .env)"
  exit 0
fi

# --- Volúmenes dueños de la capa ---
# Lee 'volumes:' de compose_de(); un servicio que solo MONTA un volumen ajeno no lo vuelve dueño.

volumenes_de_capa() { bloque_yaml volumes $(compose_de "$1"); }

# --- Nombre declarado → nombre real ---
# Compose prefija con el proyecto ('pgdata' → 'production_pgdata'); el mapa sale ya resuelto.

cargar_mapa_volumenes() {
  [ -n "${MAPA_VOLUMENES+x}" ] && return 0
  MAPA_VOLUMENES=$(docker compose config 2>/dev/null | awk '
    /^volumes:/ {enbloque=1; next}
    enbloque && /^[a-zA-Z]/ {enbloque=0}
    enbloque && /^  [a-zA-Z0-9_.-]+:/ {decl=$1; sub(/:$/,"",decl); next}
    enbloque && decl != "" && /^    name:/ {print decl, $2; decl=""}
  ')
}

nombres_reales() {
  local decl real
  for decl in $1; do
    real=$(printf '%s\n' "$MAPA_VOLUMENES" | awk -v d="$decl" '$1==d {print $2; exit}')
    [ -n "$real" ] && printf '%s\n' "$real"
  done
}

# --- Nuke de una capa ---
# Borra por nombre real: 'docker volume rm -f' sobre un nombre inexistente sale con 0 en
# silencio, así que usar el declarado dejaría los datos en disco y reportaría éxito igual.

nuke_capa() {
  local decl reales="" imgs err
  decl=$(volumenes_de_capa "$CAPA" | tr '\n' ' '); decl="${decl% }"

  if [ -n "$decl" ]; then
    cargar_mapa_volumenes
    reales=$(nombres_reales "$decl" | tr '\n' ' '); reales="${reales% }"
    if [ -z "$reales" ]; then
      ui_bad "no se pudo resolver el nombre real de los volúmenes ($decl)" \
             "¿docker responde? sin eso el nuke borraría los containers y dejaría los datos"
      return 1
    fi
  fi

  echo "Se van a borrar de la capa $CAPA: containers ($presentes), imágenes, y volúmenes (${reales:-ninguno})."
  echo "addons/ y state/ NO se tocan acá — eso es 'make nuke' (global), no un nuke por capa."
  ui_confirm_nuke || return 1

  imgs=$(docker compose images -q $presentes 2>/dev/null | sort -u | tr '\n' ' '); imgs="${imgs% }"

  docker compose rm -sf $presentes || return $?
  if [ -n "$reales" ]; then docker volume rm -f $reales || return $?; fi

  # --- Imágenes: aviso, nunca fallo ---
  # Una imagen compartida (restore-db/postgres) puede seguir en uso; es reconstruible, no amerita fallar.

  if [ -n "$imgs" ]; then
    if ! err=$(docker rmi -f $imgs 2>&1); then
      ui_warn "alguna imagen quedó sin borrar (¿en uso por otra capa?)" "$(printf '%s' "$err" | head -1)"
    fi
  fi
  return 0
}

case "$VERBO" in
  up)      ui_run "$CAPA-up" docker compose up -d $presentes ;;
  down)    ui_run "$CAPA-down" docker compose rm -sf $presentes ;;
  restart) ui_run "$CAPA-restart" docker compose restart $presentes ;;
  ps)
    ui_start "$CAPA-ps"
    docker compose ps $presentes --format "table {{.Name}}\t{{.Service}}\t{{.Status}}" | ui_color_status
    ec=$?
    if [ "$ec" -eq 0 ]; then ui_ok "$CAPA-ps listo"; else ui_bad "$CAPA-ps falló" "exit $ec"; exit "$ec"; fi
    ;;
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
