#!/usr/bin/env bash
# Helpers de verificación, compartidos por el verify de cada stack y por el
# orquestador. NO decide qué se chequea ni qué se espera: eso es de cada
# stacks/<nombre>/verify.sh. Acá viven los derivadores —qué se corre, qué se
# omite y por qué— y el vocabulario de salida.

# Sin -e a propósito: un verificador que aborta en el primer fallo esconde el resto
# del diagnóstico, que es justo para lo que se lo corre.
set -uo pipefail

# Dos niveles: este archivo vive en scripts/lib/, todo lo demás se nombra desde el root.
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
. scripts/lib/ui.sh

# --- Guarda de doble sourceo ---
# El orquestador sourcea el verify de cada stack, y cada uno sourcea esta librería.
# Sin la guarda, cada stack resetea PASS/FALLO/AVISO y el resumen final reporta
# solo los del último — se midió: 11 fallas salían como 2. Además evita repetir
# la consulta a la composición, que es un subproceso por stack.

[ -n "${VERIFY_LIB_CARGADA:-}" ] && return 0
VERIFY_LIB_CARGADA=1
# --- Valores por deployment ---
# Los lee de .env solo, para que ninguna verificación dependa de la shell del operador.

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi

PUBLIC_HOSTNAME="${PUBLIC_HOSTNAME:-}"
LOCAL_IP="${LOCAL_IP:-}"

PASS=0; FALLO=0; AVISO=0

# --- Salida ---
# Un renglón por chequeo; el motivo del fallo va debajo, indentado.

ok()     { ui_ok "$1"; PASS=$((PASS+1)); }
bad()    { ui_bad "$1" "$2"; FALLO=$((FALLO+1)); }
aviso()  { ui_warn "$1" "$2"; AVISO=$((AVISO+1)); }
omitir() { ui_skip "$1 ($2)"; }
titulo() { ui_title "$1"; }

# --- Helpers ---
# expect corre el comando y exige que su salida contenga el patrón; vacio exige lo contrario.

expect() {
  local nombre="$1" patron="$2"; shift 2
  local salida
  if ! salida=$("$@" 2>&1); then
    bad "$nombre" "el comando falló: $(printf '%s' "$salida" | head -1)"
    return
  fi
  case "$salida" in
    *"$patron"*) ok "$nombre" ;;
    *) bad "$nombre" "esperaba '$patron', obtuve: $(printf '%s' "$salida" | head -1)" ;;
  esac
}

vacio() {
  local nombre="$1"; shift
  local salida
  salida=$("$@" 2>/dev/null)
  if [ -z "$salida" ]; then ok "$nombre"
  else bad "$nombre" "$(printf '%s' "$salida" | head -2 | tr '\n' ' ')"; fi
}

# --- ¿El servicio está en este stack? ---
# Le pregunta a la composición, como las guardas del Makefile: qué stacks trae cada
# entorno ya lo dice su entrypoint. Un stack que este entorno no lleva no es un fallo.
#
# Los perfiles se fusionan en la VARIABLE, no con --profile: un --profile explícito
# REEMPLAZA a COMPOSE_PROFILES en vez de sumarse — se midió. Con flags, un deploy
# con COMPOSE_PROFILES=lan perdía dnsmasq de esta lista y nunca se verificaba.
#
# cert y restore van siempre porque son operaciones a demanda: el perfil las
# mantiene fuera de `up`, pero son parte del stack igual. Lo que traiga el
# operador —lan— es topología, y ahí sí manda su .env.

SERVICIOS=$(COMPOSE_PROFILES="cert,restore${COMPOSE_PROFILES:+,$COMPOSE_PROFILES}" \
  docker compose config --services 2>/dev/null)

# Sin composición no se aborta: es el estado que la capa host existe para
# diagnosticar. Se responde que sí a todo y cada chequeo reporta su propio fallo.

declarado() {
  [ -z "$SERVICIOS" ] && return 0
  printf '%s\n' "$SERVICIOS" | grep -qx "$1"
}

# --- ¿El servicio está levantado? ---
# Un chequeo de runtime contra un servicio apagado no puede concluir nada: dar ok
# seria mentir y dar FALLA seria culpar al chequeo equivocado. Se omite.

corriendo() { [ -n "$(docker compose ps -q "$1" 2>/dev/null)" ]; }

# --- Por qué se omite ---
# Distingue las dos causas: una capa ausente es una decisión del entorno, un
# servicio caído es un problema. Confundirlas manda a buscar al lugar equivocado.

motivo() {
  if declarado "$1"; then echo "$1 no está corriendo"; else echo "$1 no está en este stack"; fi
}

# --- Búsqueda en logs ---
# Helper propio porque vacio() no puede llevar un pipe: acá el grep es parte del chequeo.
#
# El tercer argumento es la excepción: el patrón que, aun matcheando, no cuenta como
# error. Vacío exige el log limpio entero. Un error por diseño no puede quedar rojo.

log_limpio() {
  local nombre="$1" patron="$2" salvo="$3"; shift 3
  local salida
  if ! corriendo "$1"; then omitir "$nombre" "$(motivo "$1")"; return; fi
  salida=$(docker compose logs --tail 500 --no-log-prefix "$@" 2>/dev/null | grep -iE "$patron")
  [ -n "$salvo" ] && salida=$(printf '%s\n' "$salida" | grep -viE "$salvo")
  if [ -z "$salida" ]; then ok "$nombre"
  else bad "$nombre" "$(printf '%s' "$salida" | head -1)"; fi
}

# --- Estado de un servicio ---
# Distingue "no levantado" de "unhealthy": el primero es una capa que falta, el segundo un fallo.

sano() {
  local svc="$1" estado
  if ! declarado "$svc"; then omitir "$svc levantado" "no está en este stack"; return 1; fi
  estado=$(docker compose ps "$svc" --format '{{.Status}}' 2>/dev/null | head -1)
  if [ -z "$estado" ]; then bad "$svc levantado" "no está corriendo"; return 1; fi
  case "$estado" in
    *"(healthy)"*)          ok "$svc healthy" ;;
    *"health: starting"*)   aviso "$svc healthy" "todavía en start_period" ;;
    *"(unhealthy)"*)        bad "$svc healthy" "unhealthy — docker compose logs $svc" ;;
    Up*)                    ok "$svc up (sin healthcheck propio)" ;;
    *)                      bad "$svc levantado" "$estado" ;;
  esac
  return 0
}

# --- Binds ---
# El acceso lo define la IP publicada, no el firewall (PRINCIPLES.md, Seguridad). Un 0.0.0.0 es un hallazgo.

# Un puerto sin publicar NO devuelve vacío: docker compose port imprime "invalid IP:0"
# y sale con 0. Tomarlo como publicado marca en rojo todos los puertos internos.

publicado_en() {
  local salida
  salida=$(docker compose port "$1" "$2" 2>/dev/null | head -1)
  case "$salida" in
    ''|invalid*|*:0) return 1 ;;
    *) printf '%s' "${salida%:*}"; return 0 ;;
  esac
}

# --- ¿El stack publica ESE puerto, y en qué IP? ---
# No lo publican todos: staging borra el bloque entero y development deja solo el 80,
# porque server-plain no escucha en el 443. El $ ancla: "target: 80" matchea 8069.

# La IP esperada sale de la composición resuelta y NO de repetir la cadena de defaults
# del .env: development pisa el ports: con !override y su cadena no consulta LOCAL_IP.

# Sin composición legible imprime '?' y devuelve 0, como declarado(): falla abierta
# para que el chequeo reporte su propio fallo y no uno inventado sobre las capas.

bind_declarado() {
  local bloque
  bloque=$(docker compose config 2>/dev/null | sed -n "/^  $1:$/,/^  [a-z_-]*:$/p")
  [ -z "$bloque" ] && { echo '?'; return 0; }
  printf '%s\n' "$bloque" | grep -qE "target: $2\$" || return 1
  printf '%s\n' "$bloque" | grep -B1 -E "target: $2\$" | sed -n 's/^ *host_ip: //p' | head -1 \
    | grep . || echo '0.0.0.0'
}

# --- ¿El daemon rota logs? ---
# Solo busca el límite de tamaño, no compara el archivo entero: un host con claves
# propias (data-root, registry-mirrors) es legítimo y no tiene por qué dar rojo.

rotacion_aplicada() { grep -q '"max-size"' "${DAEMON_JSON:-/etc/docker/daemon.json}" 2>/dev/null; }

# --- ¿Este stack sirve TLS? ---
# Qué config monta nginx lo dice la composición, no .env: development la fija en
# su entrypoint, así que su .env puede no traer NGINX_MODE y el modo se sabe igual.
#
# El nombre no lleva .template: los config de nginx son archivos reales,
# bootstrapeados con cp desde su .example — ya no pasan por envsubst.

modo_plain() {
  docker compose config 2>/dev/null | grep -q 'source:.*/server-plain\.conf$'
}

# --- ¿Este stack manda correo? ---
# Lo dice la composición, no .env: staging y development fuerzan ODOO_DISABLE_SMTP,
# y con eso el entrypoint escribe smtp_server vacío pase lo que pase en odoo.conf.

smtp_activo() {
  ! docker compose config 2>/dev/null | grep -q 'ODOO_DISABLE_SMTP: *"1"'
}

# --- Placeholder de un .example sin reemplazar ---
# Los config reales se bootstrapean con cp y se editan a mano: si quedó el
# placeholder, la herramienta arranca igual con un valor inservible.
#
# El archivo ausente NO es ok: es el bootstrap sin hacer, y Compose monta un
# directorio en su lugar. Da fallo propio, no el verde de un grep que no matcheó.

sin_placeholder() {
  local nombre="$1" archivo="$2" patron="$3" hallado
  if [ ! -f "$archivo" ]; then
    bad "$nombre" "falta $archivo — bootstrapealo con cp desde su .example"
    return
  fi
  # Los comentarios se descartan ANTES de buscar: el .example de cada herramienta
  # dice "Reemplazá TU_X por..." en un comentario que sigue ahí después de haber
  # reemplazado el valor. Sin esto el chequeo no podía pasar nunca — se midió
  # contra grafana.ini con todos sus valores ya cargados.
  hallado=$(sed -E 's@^[[:space:]]*([;#]|//).*@@' "$archivo" | grep -oE "$patron" | sort -u | tr '\n' ' ')
  if [ -n "$hallado" ]; then bad "$nombre" "sigue ${hallado% } sin reemplazar"
  else ok "$nombre"; fi
}

bind_es() {
  local svc="$1" puerto="$2" esperado actual
  if ! esperado=$(bind_declarado "$svc" "$puerto"); then
    omitir "$svc:$puerto publicado" "este stack no lo publica"; return
  fi
  if ! corriendo "$svc"; then omitir "$svc:$puerto publicado en $esperado" "$(motivo "$svc")"; return; fi
  if ! actual=$(publicado_en "$svc" "$puerto"); then
    bad "$svc:$puerto publicado en $esperado" "no está publicado"; return
  fi
  # --- 0.0.0.0 ---
  # Rama propia y antes de comparar: coincidir con lo declarado no lo salva, porque
  # el criterio no es "corre lo que dice la composición" sino "no en toda interfaz".

  if [ "$actual" = "0.0.0.0" ]; then
    bad "$svc:$puerto con bind acotado" "está en 0.0.0.0 — expuesto en todas las interfaces"
  elif [ "$actual" = "$esperado" ]; then ok "$svc:$puerto publicado en $esperado"
  else bad "$svc:$puerto publicado en $esperado" "está en $actual — viola el criterio de bind"; fi
}

sin_publicar() {
  local svc="$1" puerto="$2" actual
  if ! corriendo "$svc"; then omitir "$svc:$puerto sin publicar" "$(motivo "$svc")"; return; fi
  if actual=$(publicado_en "$svc" "$puerto"); then
    bad "$svc:$puerto sin publicar" "está publicado en $actual"
  else ok "$svc:$puerto sin publicar"; fi
}

# --- Timers de systemd ---
# El nombre instalado lo deriva timers.sh, que es su dueño: acá solo se pregunta si
# el que corresponde a este stack está activo y si su fallo avisa.

PLANTILLA_AVISO_VISTA=0

timer_activo() {
  local base="$1" unidad notify
  if ! command -v systemctl >/dev/null 2>&1; then
    omitir "timer $base activo" "sin systemd"; return
  fi
  # Sin composición legible, timers.sh sale con 1: decir "no corresponde" ahí sería mentir.
  if ! unidad=$(scripts/timers.sh units 2>/dev/null); then
    omitir "timer $base activo" "no se pudo leer la composición"; return
  fi
  unidad=$(printf '%s\n' "$unidad" | grep -- "-$base\$")
  if [ -z "$unidad" ]; then
    omitir "timer $base activo" "no corresponde a este stack"; return
  fi

  # --full: sin tty systemd asume 80 columnas y recorta la columna UNIT con '…'.
  # Con el proyecto adelante el nombre ya no entra, y el chequeo fallaría sobre un timer sano.
  expect "timer $base activo ($unidad.timer)" "$unidad.timer" \
    systemctl list-timers --all --full --no-pager "$unidad.timer"

  # Un OnFailure= que nombre la plantilla de otro checkout deja el aviso mudo.
  notify=$(scripts/timers.sh notify)
  expect "fallo de $base cableado a $notify" "$notify" systemctl cat "$unidad.service"

  # La plantilla es una sola por stack: se chequea con el primer timer que la use.
  [ "$PLANTILLA_AVISO_VISTA" -eq 1 ] && return
  PLANTILLA_AVISO_VISTA=1
  expect "unit plantilla de aviso instalada" "$notify" \
    systemctl list-unit-files --full --no-pager "$notify*"
}


# --- Resumen ---
# El exit code es lo que consume el operador: 0 = la capa está sana.

resumen() {
  local linea="$PASS ok · $FALLO fallas · $AVISO avisos"
  if [ "$FALLO" -eq 0 ]; then printf '\n%s✓%s %s\n' "$UI_GREEN" "$UI_RESET" "$linea"
  else printf '\n%s✗%s %s\n' "$UI_RED" "$UI_RESET" "$linea"; fi
  [ "$FALLO" -eq 0 ]
}
