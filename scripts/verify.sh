#!/usr/bin/env bash
# Verificación del deploy, una capa por subcomando. Dueño único de qué se chequea
# y de qué se espera: docs/runbooks/ nombra el comando, los valores viven acá.

# Sin -e a propósito: un verificador que aborta en el primer fallo esconde el resto
# del diagnóstico, que es justo para lo que se lo corre.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh

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
# Le pregunta a la composición, como las guardas del Makefile: qué capas trae cada
# entorno ya lo dice su entrypoint. Una capa que este stack no lleva no es un fallo.

SERVICIOS=$(docker compose --profile cert --profile restore config --services 2>/dev/null)

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

log_limpio() {
  local nombre="$1" patron="$2"; shift 2
  local salida
  if ! corriendo "$1"; then omitir "$nombre" "$(motivo "$1")"; return; fi
  salida=$(docker compose logs --tail 500 --no-log-prefix "$@" 2>/dev/null | grep -iE "$patron")
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

# --- ¿Este stack sirve TLS? ---
# Qué plantilla monta nginx lo dice la composición, no .env: development la fija en
# su entrypoint, así que su .env puede no traer NGINX_MODE y el modo se sabe igual.

modo_plain() {
  docker compose config 2>/dev/null | grep -q 'source:.*/server-plain\.conf\.template$'
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

# =====================================================================
# host — prerrequisitos del servidor, antes de levantar cualquier capa
# =====================================================================

v_host() {
  titulo "host"

  # --- Compose ---
  # La directiva include: de docker/compose.yaml exige v2.20 o superior.

  local v mayor menor
  v=$(docker compose version --short 2>/dev/null)
  if [ -z "$v" ]; then
    bad "docker compose disponible" "no responde — ¿está el daemon corriendo?"
  else
    mayor=${v%%.*}; menor=${v#*.}; menor=${menor%%.*}
    if [ "$mayor" -gt 2 ] || { [ "$mayor" -eq 2 ] && [ "$menor" -ge 20 ]; }; then
      ok "docker compose $v (>= 2.20, exigido por include:)"
    else
      bad "docker compose >= 2.20" "es $v — include: no funciona"
    fi
  fi

  # --- Arranque automático ---
  # Sin esto el stack no vuelve solo después de un reinicio del servidor.

  if command -v systemctl >/dev/null 2>&1; then
    expect "docker habilitado al boot" "enabled" systemctl is-enabled docker
  else
    omitir "docker habilitado al boot" "sin systemd"
  fi

  # --- .env ---
  # Compose interpola una variable vacía sin fallar; el síntoma aparece capas después.

  local vacias
  vacias=$(grep -nE '^[A-Z0-9_]+=$' .env 2>/dev/null | cut -d: -f2 | tr '\n' ' ')
  if [ ! -f .env ]; then bad ".env presente" "no existe — cp .env.<entorno>.example .env"
  elif [ -n "$vacias" ]; then bad ".env sin claves vacías" "vacías: $vacias"
  else ok ".env sin claves vacías"; fi

  # --- Destinatario de las alertas ---
  # Grafana lo interpola al leer el contact point y sin dirección el provisioning
  # aborta: no arranca, sale con 1 y el restart lo reintenta para siempre. Se
  # chequea acá, antes de levantar capa alguna, porque el de arriba solo ve la
  # clave presente y vacía, y la que rompe igual es la que no está.

  if ! declarado grafana; then
    omitir "ALERT_EMAIL_TO declarado" "sin Grafana en este stack"
  elif [ -n "${ALERT_EMAIL_TO:-}" ]; then
    ok "ALERT_EMAIL_TO declarado ($ALERT_EMAIL_TO)"
  else
    bad "ALERT_EMAIL_TO declarado" "falta o está vacío en .env — Grafana no arranca: el provisioning de alerting aborta"
  fi

  # --- Identidad del stack ---
  # Un nombre vacío es una composición que no resuelve, no un nombre que falta: sin
  # COMPOSE_PROJECT_NAME el proyecto sale del directorio del compose, siempre 'docker'.

  local proyecto
  proyecto=$(docker compose config 2>/dev/null | sed -n 's/^name: //p' | head -1)
  if [ -z "$proyecto" ]; then
    bad "la composición resuelve" \
        "COMPOSE_FILE=${COMPOSE_FILE:-sin declarar} no resuelve — ningún target del Makefile va a andar"
  elif grep -qE '^COMPOSE_PROJECT_NAME=.+' .env 2>/dev/null; then
    ok "identidad declarada en .env (proyecto: $proyecto, capas: ${COMPOSE_FILE:-sin declarar})"
  else
    aviso "identidad declarada en .env" \
          "falta COMPOSE_PROJECT_NAME — el proyecto sale del directorio del compose: $proyecto"
  fi

  # --- Secrets ---
  # Delegado: scripts/secrets-perms.sh es el dueño único del mapa de GIDs.

  if scripts/secrets-perms.sh --check >/dev/null 2>&1; then
    ok "secrets con permisos, grupo y valor cargado"
  else
    bad "secrets con permisos, grupo y valor cargado" "correr: scripts/secrets-perms.sh --check"
  fi

  # --- ufw ---
  # Solo gobierna puertos de procesos del host; acá el 53/udp de dnsmasq.

  if ! declarado dnsmasq; then
    omitir "ufw permite 53/udp desde la LAN" "sin dnsmasq en este stack"
  elif command -v ufw >/dev/null 2>&1; then
    if sudo -n ufw status 2>/dev/null | grep -q '53/udp'; then
      ok "ufw permite 53/udp desde la LAN"
    else
      aviso "ufw permite 53/udp desde la LAN" "no se pudo confirmar (¿sudo?) — sudo ufw status | grep 53"
    fi
  else
    omitir "ufw permite 53/udp desde la LAN" "sin ufw"
  fi

  # --- Superficie real del host ---
  # Incluye contenedores ajenos a este repo: ufw no los alcanza, publican por DNAT.

  local ps_out expuestos
  if ! ps_out=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null); then
    omitir "ningún contenedor publica en 0.0.0.0" "el daemon no responde"
    return
  fi
  expuestos=$(printf '%s\n' "$ps_out" | grep '0\.0\.0\.0' | awk '{print $1}' | tr '\n' ' ')
  if [ -z "$expuestos" ]; then ok "ningún contenedor publica en 0.0.0.0"
  else aviso "contenedores publicando en 0.0.0.0" "expuestos: $expuestos "; fi
}

# =====================================================================
# edge — dnsmasq, nginx, cloudflared y el certificado
# =====================================================================

v_edge() {
  titulo "edge"

  sano nginx; sano cloudflared; sano dnsmasq

  # --- Resolver de la LAN ---
  # El healthcheck de dnsmasq le pregunta a él: prueba que responde, no que se lo consulte.

  if declarado dnsmasq; then
    omitir "la LAN usa dnsmasq como resolver" \
      "no verificable desde el servidor — correr el chequeo de docs/runbooks/entorno/levantar-produccion.md fase 2 en un equipo de la LAN"
  fi

  # --- Config renderizada ---
  # envsubst corre al arrancar: si el filtro o la variable fallan, nginx levanta
  # igual con el literal ${PUBLIC_HOSTNAME} adentro y sirve un server_name inútil.

  if corriendo nginx; then
    vacio "sin variables sin sustituir en la config" \
      docker compose exec -T nginx grep -rl '\${' /etc/nginx/conf.d/
    if modo_plain; then
      omitir "server_name es el hostname público" "modo plain: el server_name es el catch-all, no hay hostname que servir"
    elif [ -n "$PUBLIC_HOSTNAME" ]; then
      expect "server_name es el hostname público" "$PUBLIC_HOSTNAME" \
        docker compose exec -T nginx grep -h server_name /etc/nginx/conf.d/default.conf
    else
      omitir "server_name es el hostname público" "falta PUBLIC_HOSTNAME en .env"
    fi
  else
    omitir "sin variables sin sustituir en la config" "$(motivo nginx)"
    omitir "server_name es el hostname público" "$(motivo nginx)"
  fi

  # --- Resolver dinámico ---
  # Sin resolver + proxy_pass por variable, nginx cachea la IP de Odoo al arrancar
  # y devuelve 502 en cuanto el contenedor se recrea, hasta que alguien lo recargue.

  vacio "proxy_pass va por variable, no por nombre fijo" \
    grep -nE 'proxy_pass +http://odoo' config/nginx/odoo.locations.template
  expect "resolver de Docker declarado" "127.0.0.11" \
    grep -h resolver config/nginx/00-http.conf.template

  # --- Certificado ---
  # Lo emite certbot, no nginx: si falta, nginx ni siquiera arranca. Se avisa
  # antes de que el timer sea el que descubra el problema.

  local venc epoch ahora dias
  if ! declarado certbot; then
    omitir "certificado emitido" "sin certbot en este stack — nginx sirve en texto plano"
  else
    venc=$(docker compose --profile cert run --rm -T certbot certificates 2>/dev/null \
      | sed -n 's/.*Expiry Date: \([^ ]* [^ ]*\).*/\1/p' | head -1)
    if [ -z "$venc" ]; then
      bad "certificado emitido" "certbot no reporta ninguno — correr make cert-issue"
    else
      epoch=$(date -u -d "$venc" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d %H:%M:%S' "$venc" +%s 2>/dev/null || echo 0)
      ahora=$(date -u +%s); dias=$(( (epoch - ahora) / 86400 ))
      if [ "$epoch" -eq 0 ]; then aviso "certificado emitido" "no se pudo interpretar la fecha: $venc"
      elif [ "$dias" -lt 15 ]; then bad "certificado vigente" "vence en $dias días — la renovación no está corriendo"
      else ok "certificado vigente ($dias días)"; fi
    fi
  fi

  # --- Túnel ---
  # Cuatro conexiones registradas es lo normal; una sola funciona pero está degradado.

  local conns
  if ! declarado cloudflared; then
    omitir "cloudflared con >=2 conexiones" "sin túnel en este stack"
  else
    conns=$(docker compose logs cloudflared 2>/dev/null | grep -c "Registered tunnel connection")
    if [ "${conns:-0}" -ge 2 ]; then ok "cloudflared con $conns conexiones registradas"
    elif [ "${conns:-0}" -eq 1 ]; then aviso "cloudflared con >=2 conexiones" "solo 1 — degradado"
    else bad "cloudflared con >=2 conexiones" "0 — el Tunnel no conecta"; fi
  fi

  log_limpio "nginx sin errores en el log" '\[error\]|\[emerg\]' nginx

  # --- Binds ---
  # Nivel 3 (LAN): el acceso local esquiva el túnel y necesita llegar al proxy. La
  # dirección esperada es la misma que arma el ports: de docker/compose.proxy.yaml.

  # El esperado no se declara acá: lo lee bind_es de la composición resuelta, que es
  # la única que sabe qué cadena de defaults aplicó el entrypoint de ESTE stack.

  bind_es nginx 80
  bind_es nginx 443

  # --- Bind caído al default ---
  # El loopback de docker/compose.proxy.yaml es una red de contención, no una configuración:
  # sin LOCAL_IP el proxy deja de atender la LAN y el esperado cae con él, en verde.

  if bind_declarado nginx 443 >/dev/null && [ -z "${HTTP_BIND:-}${HTTPS_BIND:-}${LOCAL_IP:-}" ]; then
    bad "LOCAL_IP declarada en .env" \
        "falta y este stack publica el 443 — nginx cae al loopback y no atiende la LAN"
  fi

  # --- Token de Cloudflare ---
  # Valor y alcance de una sola vez, contra la API real. Lo consume certbot para
  # el desafío DNS-01: un token inválido no se nota hasta que el cert no renueva.

  # /user/tokens/verify rechaza los tokens nuevos con prefijo cfut_ aunque
  # sean válidos — se prueba contra /zones, lo mismo que usa certbot de verdad.

  local token resp
  if ! declarado certbot; then
    omitir "token de Cloudflare activo" "sin certbot en este stack — no hay desafío DNS-01 que firmar"
  elif token=$(cat secrets/cloudflare_api_token 2>/dev/null) && [ -n "$token" ]; then
    resp=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones"\n' \
      "$token" | curl -s -m 10 --config - 2>/dev/null)
    if printf '%s' "$resp" | grep -q '"success":true'; then
      if printf '%s' "$resp" | grep -q '"count":0'; then
        bad "token de Cloudflare activo" "token válido pero sin zonas visibles — revisá el alcance (Zone Resources) del token"
      else
        ok "token de Cloudflare activo"
      fi
    elif printf '%s' "$resp" | grep -q '"code":1000'; then
      bad "token de Cloudflare activo" "1000 Invalid API Token — el valor está mal pegado"
    elif printf '%s' "$resp" | grep -q '"code":9109'; then
      bad "token de Cloudflare activo" "9109 — el token no lee la zona; rehacerlo con la plantilla Edit zone DNS"
    else
      bad "token de Cloudflare activo" "respuesta inesperada de la API"
    fi
  else
    omitir "token de Cloudflare activo" "secret ilegible — correr con sudo"
  fi
}

# =====================================================================
# db — postgres, pgbouncer + archivado de pgBackRest
# =====================================================================

v_db() {
  titulo "db"

  sano postgres; sano pgbouncer

  expect "postgres acepta conexiones" "accepting connections" \
    docker compose exec -T postgres pg_isready

  # --- Autenticación real a través de PgBouncer ---
  # pg_isready no autentica: un auth_file ilegible lo pasa igual y el fallo
  # aparece recién en la capa de Odoo, como un error que no menciona a PgBouncer.

  expect "auth real por PgBouncer" "1" docker compose exec -T postgres sh -c \
    'PGPASSWORD=$(cat /run/secrets/postgres_password) psql -h pgbouncer -p 6432 -U odoo -d postgres -tAc "select 1"'

  log_limpio "sin errores de permisos ni auth_file" 'permission denied|could not open auth_file' postgres pgbouncer

  # --- Archivado de WAL ---
  # archive_mode es parámetro de postmaster: cambiarlo exige reinicio, no reload.
  #
  # Lo que se espera depende del stack, y en el que no respalda es lo más caro de
  # descubrir tarde: apunta a la stanza de producción para restaurar, así que con
  # el archivado prendido le empuja su propio WAL al repo del entorno real.

  if declarado backup; then
    expect "archive_mode activo" "on" docker compose exec -T postgres \
      psql -U odoo -tAc "SHOW archive_mode"
    expect "archive_command hacia pgBackRest" "pgbackrest archive-push" \
      docker compose exec -T postgres psql -U odoo -tAc "SHOW archive_command"
  else
    expect "archive_mode APAGADO (stack sin backups)" "off" docker compose exec -T postgres \
      psql -U odoo -tAc "SHOW archive_mode"
  fi

  # --- Stanza ---
  # cipher confirma que el repo está cifrado; el rango de wal archive, que el
  # archive_command llega de verdad a R2 y no solo parsea.

  # --- Stanza y opciones del cluster ---
  # pgbackrest.conf no trae sección de stanza: el nombre y pg1-path llegan por
  # entorno. Sin pg1-path resuelto el archivado muere sin que la config parezca rota,
  # y `help` es la única forma de leer el valor efectivo sin tocar el repositorio.

  # Producción archiva y restaura, staging solo restaura, development ninguna de las
  # dos: sin pgBackRest en juego, la stanza no es un dato que falte.

  local stanza="${PGBACKREST_STANZA:-}"
  if ! declarado backup && ! declarado restore-db; then
    omitir "stanza declarada en .env" "este stack no archiva ni restaura"
  elif [ -z "$stanza" ]; then
    bad "stanza declarada en .env" "PGBACKREST_STANZA vacío"
  else
    ok "stanza '$stanza' declarada en .env"
    expect "pg1-path resuelto por entorno" "current: /var/lib/postgresql/data" \
      docker compose exec -T -u postgres postgres pgbackrest help archive-push pg1-path
  fi

  # --- Coherencia de las dos retenciones ---
  # El techo de pgBackRest no es un número elegido: tiene que cubrir la ventana de
  # restic, o un restore de la base se queda sin filestore de esa fecha. Los dos
  # valores viven en archivos de herramientas distintas y nada más los ata.

  local dia sem mes cobertura ret
  if ! declarado backup; then
    omitir "retención de la base cubre la del filestore" "este stack no escribe backups"
  else
    dia="${RESTIC_KEEP_DAILY:-7}"
    sem="${RESTIC_KEEP_WEEKLY:-4}"
    mes="${RESTIC_KEEP_MONTHLY:-3}"
    ret="${BACKUP_RETENTION_DAYS:-125}"
    cobertura=$(( dia + sem * 7 + mes * 30 ))
    if [ "$ret" -ge "$cobertura" ]; then
      ok "retención de la base ($ret d) cubre la del filestore ($cobertura d)"
    else
      bad "retención de la base cubre la del filestore" \
          "base $ret d < filestore $cobertura d — un restore viejo se queda sin adjuntos"
    fi
  fi

  # --- process-max contra los cpus del contenedor ---
  # Si supera el cap, pgBackRest compite con la base durante el backup.

  local pmax pcpus
  pmax=$(sed -n 's/^process-max[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' \
         config/pgbackrest/pgbackrest.conf | head -1)
  pcpus=$(sed -n '/^  postgres:/,/^  [a-z]/p' docker/compose.db.yaml | sed -n 's/.*cpus: "\([0-9.]*\)".*/\1/p' | head -1)
  if ! declarado backup && ! declarado restore-db; then
    omitir "process-max dentro de los cpus de postgres" "este stack no corre pgBackRest"
  elif [ -z "$pmax" ] || [ -z "$pcpus" ]; then
    aviso "process-max dentro de los cpus de postgres" "no se pudieron leer los valores"
  elif awk -v a="$pmax" -v b="$pcpus" 'BEGIN{exit !(a<=b)}'; then
    ok "process-max ($pmax) dentro de los cpus de postgres ($pcpus)"
  else
    bad "process-max dentro de los cpus de postgres" \
        "process-max $pmax > cpus $pcpus — pgBackRest compite con la base"
  fi

  # El cipher solo no alcanza: pgbackrest lo imprime desde la config local aunque
  # el repositorio sea inalcanzable, así que un `ok` ahí tapaba una stanza en error.
  #
  # Solo lo corre el stack que respalda: los otros apuntan a la stanza de
  # producción, así que acá darían verde por un repositorio que no es suyo.

  local info detalle
  if ! declarado backup; then
    omitir "repositorio de pgBackRest alcanzable y cifrado" \
      "este stack no escribe backups — el repo es el de producción y lo verifica producción"
  else
    info=$(docker compose exec -T -u postgres postgres pgbackrest info 2>&1)
    case "$info" in
      *"no valid backup"*)
        omitir "repositorio de pgBackRest alcanzable y cifrado" \
          "sin backups todavía — normal antes de la fase 6; el archive_command ya llega (ver 'wal archive min/max')" ;;
      *"status: error"*)
        detalle=$(printf '%s' "$info" | grep -o '\[[A-Za-z]*Error\].*' | head -1)
        [ -n "$detalle" ] || detalle=$(printf '%s' "$info" | grep 'status: error' | head -1 | sed 's/^ *//')
        bad "repositorio de pgBackRest alcanzable y cifrado" "$detalle" ;;
      *aes-256-cbc*) ok "repositorio de pgBackRest alcanzable y cifrado (aes-256-cbc)" ;;
      *) bad "repositorio de pgBackRest alcanzable y cifrado" \
             "pgbackrest info no reporta cipher: $(printf '%s' "$info" | head -1)" ;;
    esac
  fi

  local ready
  if ! corriendo postgres; then
    omitir "sin WAL pendiente de archivar" "postgres no está corriendo"
  elif ! ready=$(docker compose exec -T postgres sh -c \
       'ls /var/lib/postgresql/data/pg_wal/*.ready 2>/dev/null | wc -l' 2>/dev/null | tr -d ' \r'); then
    bad "sin WAL pendiente de archivar" "no se pudo consultar el directorio de WAL"
  elif [ "${ready:-0}" -eq 0 ]; then ok "sin WAL pendiente de archivar"
  else bad "sin WAL pendiente de archivar" "$ready archivos .ready — el archivado está roto y el disco se llena"; fi

  # --- Binds ---
  # Nivel 1: solo por nombre dentro de la red app, nunca publicados.

  sin_publicar postgres 5432
  sin_publicar pgbouncer 6432
}

# =====================================================================
# odoo — la aplicación y la cadena pública
# =====================================================================

v_odoo() {
  titulo "odoo"

  sano odoo

  log_limpio "sin errores de permisos" 'permission denied' odoo

  expect "odoo sirve en :8069" "200" docker compose exec -T odoo \
    curl -sS -o /dev/null -w '%{http_code}' http://localhost:8069/web/login

  # --- Árbol de addons ---
  # Llegan por bind-mount: su presencia ya no la garantiza la imagen.

  local estado sucios faltan
  estado=$(scripts/addons.sh status 2>/dev/null | grep -E '^(enterprise|custom-addons|oca|third-party)[[:space:]]')
  sucios=$(printf '%s\n' "$estado" | awk '$NF=="sucio" {print $2}' | tr '\n' ' ')
  faltan=$(printf '%s\n' "$estado" | grep 'sin worktree' | awk '{print $2}' | tr '\n' ' ')
  if [ -z "$estado" ]; then
    bad "worktrees del checkout presentes" "árbol vacío — correr make addons-sync"
  elif [ -n "$faltan" ]; then
    bad "worktrees del checkout presentes" "sin clonar: $faltan — correr make addons-sync"
  elif [ -n "$sucios" ]; then
    bad "worktrees del checkout limpios" "sucios: $sucios — addons.sh no actualiza un worktree con cambios"
  else
    ok "worktrees del checkout presentes y limpios"
  fi

  # --- Módulos server-wide presentes en el árbol ---
  # Odoo NO falla si uno no existe: loguea el error y sigue. El síntoma aparece
  # lejos de la causa — el bus deja de actualizar en tiempo real, por ejemplo.

  local swm mod hallado
  swm=$(sed -n 's/^server_wide_modules[[:space:]]*=[[:space:]]*\(.*\)/\1/p' config/odoo/odoo.conf | tr -d ' ' | tr ',' '\n')
  while read -r mod; do
    [ -n "$mod" ] || continue
    case "$mod" in base|web) continue ;; esac
    hallado=$(find addons -mindepth 3 -maxdepth 3 -type d -name "$mod" 2>/dev/null | head -1)
    if [ -n "$hallado" ]; then
      ok "módulo server-wide '$mod' presente en el árbol"
    else
      bad "módulo server-wide '$mod' presente en el árbol" \
          "no está en addons/ — Odoo arranca igual y falla en silencio"
    fi
  done <<< "$swm"

  # --- Rama de addons contra la versión de la imagen ---
  # Clonar ramas de una versión y montarlas en un Odoo de otra rompe de formas
  # raras. Prefijo y no igualdad: 19.0-stag es coherente con la imagen 19.0, y
  # 18.0 no lo es. La versión vive solo en el Dockerfile; ADDONS_BRANCH la hereda.

  local ver_img rama
  ver_img=$(sed -n 's/^FROM odoo:\([0-9.]*\).*/\1/p' docker/odoo/Dockerfile | head -1)
  rama="${ADDONS_BRANCH:-$ver_img}"
  if [ -z "$ver_img" ]; then
    aviso "ADDONS_BRANCH coherente con la imagen" "no se pudo leer el tag del Dockerfile"
  else
    case "$rama" in
      "$ver_img"|"$ver_img"-*)
        ok "ADDONS_BRANCH ($rama) coherente con la imagen ($ver_img)" ;;
      # Una rama de feature no lleva la versión en el nombre, así que no hay nada
      # que cruzar: se avisa en vez de fallar, y el operador es quien sabe de dónde salió.
      [!0-9]*)
        aviso "ADDONS_BRANCH coherente con la imagen" \
              "'$rama' no declara versión — nada garantiza que sea de la $ver_img" ;;
      *)
        bad "ADDONS_BRANCH coherente con la imagen" \
            "ADDONS_BRANCH=$rama contra imagen $ver_img" ;;
    esac
  fi

  # --- Categorías de addons ---
  # La lista vive en dos archivos: addons.sh valida contra ella y el entrypoint
  # arma el addons_path recorriéndola. Si divergen, los módulos de la categoría
  # que falta se clonan y nunca se cargan — sin error, solo no aparecen.

  local cats_sync cats_path
  cats_sync=$(sed -n 's/^[[:space:]]*\([a-z|-]*\)) return 0 ;;/\1/p' scripts/addons.sh | tr '|' '\n' | sort | tr '\n' ' ')
  cats_path=$(sed -n 's/^for category in \(.*\); do/\1/p' docker/odoo/entrypoint.sh | tr ' ' '\n' | sort | tr '\n' ' ')
  if [ -z "$cats_sync" ] || [ -z "$cats_path" ]; then
    aviso "categorías coherentes entre sync y addons_path" "no se pudieron leer las listas"
  elif [ "$cats_sync" = "$cats_path" ]; then
    ok "categorías coherentes entre sync y addons_path"
  else
    bad "categorías coherentes entre sync y addons_path" \
        "addons.sh: [$cats_sync] · entrypoint: [$cats_path]"
  fi

  # --- Rutas del proxy ---
  # Las tres: raíz, websocket al worker gevent, y el login con rate-limit. Se
  # cuentan sobre la config renderizada, que es lo que nginx está sirviendo de
  # verdad — no sobre la plantilla, que puede no haberse sustituido.

  local rutas
  if corriendo nginx; then
    rutas=$(docker compose exec -T nginx grep -c '^location' /etc/nginx/conf.d/odoo.locations 2>/dev/null | tr -d '\r ')
    if [ "${rutas:-0}" -ge 3 ]; then ok "las 3 rutas de Odoo en nginx"
    else bad "las 3 rutas de Odoo en nginx" "hay ${rutas:-0} — la config renderizada está incompleta"; fi
  else
    omitir "las 3 rutas de Odoo en nginx" "nginx no está corriendo"
  fi

  # --- Certificado que se está sirviendo ---
  # Contra el socket real, no contra el disco: es el único chequeo que ve el caso
  # "certbot renovó y nadie recargó nginx", que la métrica de textfile no cubre.
  # La dirección es la publicada, no loopback: sale de la composición, como los binds.

  local destino
  destino=$(bind_declarado nginx 443) || destino=""
  if modo_plain; then
    omitir "certificado que sirve nginx" "modo plain: la plantilla no escucha en el 443, no hay TLS que servir"
  elif [ -z "$destino" ]; then
    omitir "certificado que sirve nginx" \
      "este stack no publica el 443 — el reload tras renovar se ejercita a mano con cert-renew"
  elif [ -z "$PUBLIC_HOSTNAME" ]; then
    omitir "certificado que sirve nginx" "falta PUBLIC_HOSTNAME en .env"
  else
    local cert
    cert=$(echo | openssl s_client -connect "$destino:443" -servername "$PUBLIC_HOSTNAME" 2>/dev/null \
      | openssl x509 -noout -issuer -subject -enddate 2>/dev/null)
    case "$cert" in
      "") bad "certificado que sirve nginx" "no se pudo leer el certificado de $destino:443" ;;
      *"(STAGING)"*) bad "certificado que sirve nginx" "es de la CA de staging — reemitir sin --staging" ;;
      *"Let's Encrypt"*)
        if echo | openssl s_client -connect "$destino:443" -servername "$PUBLIC_HOSTNAME" 2>/dev/null \
           | openssl x509 -noout -checkend $((21*86400)) >/dev/null 2>&1; then
          ok "certificado de Let's Encrypt, vence en más de 21 días"
        else
          bad "certificado vigente" "vence en menos de 21 días — la renovación automática no corrió"
        fi ;;
      *) bad "certificado que sirve nginx" "emisor inesperado — ¿el certificado no es el de certbot?" ;;
    esac
  fi

  # --- Gestor de bases ---
  # Publicado en internet: tiene que estar deshabilitado por list_db = False.

  if [ -z "$PUBLIC_HOSTNAME" ]; then
    omitir "gestor de bases deshabilitado" "falta PUBLIC_HOSTNAME en .env"
  elif ! corriendo odoo; then
    omitir "gestor de bases deshabilitado" "odoo no corre — este chequeo sale al hostname público"
  else
    expect "gestor de bases deshabilitado" "disabled by the administrator" \
      curl -s -m 10 "https://$PUBLIC_HOSTNAME/web/database/manager"
  fi

  # --- Binds ---

  sin_publicar odoo 8069
  sin_publicar odoo 8072
}

# =====================================================================
# backups — restic, pgBackRest y los timers
# =====================================================================

v_backups() {
  titulo "backups"

  # La capa es exclusiva de producción: en un stack que no la trae, cada chequeo
  # de abajo fallaría por la razón equivocada. Se omite entera, no servicio a servicio.

  if ! declarado backup; then
    omitir "capa de backups" "no está en este stack — es exclusiva de producción"
    return
  fi

  sano backup

  expect "repo de restic con snapshots" "$COMPOSE_PROJECT_NAME" \
    docker compose exec -T backup restic snapshots --latest 1

  expect "pgBackRest con un full" "full backup" \
    docker compose exec -T -u postgres postgres pgbackrest info

  # --- Registro de addons en el snapshot ---
  # Sin pineo por commit, es lo único que dice a qué código corresponde el backup.

  if [ -s state/meta/addons.txt ]; then ok "registro de addons del snapshot presente"
  else aviso "registro de addons del snapshot presente" "state/meta/addons.txt vacío — lo escribe make backup"; fi

  # --- Timers ---
  # El diario a las 02:00, el mensual el día 1 a la 01:00.

  if command -v systemctl >/dev/null 2>&1; then
    expect "timer diario activo" "odoo-backup-daily.timer" \
      systemctl list-timers --all --no-pager odoo-backup-daily.timer
    expect "timer mensual activo" "odoo-backup-monthly.timer" \
      systemctl list-timers --all --no-pager odoo-backup-monthly.timer

    # Sin la unit plantilla instalada, un backup que falle no avisa y nada lo delata.
    expect "aviso de fallo cableado" "odoo-notify" \
      systemctl cat odoo-backup-daily.service
    expect "unit plantilla de aviso instalada" "odoo-notify@" \
      systemctl list-unit-files --no-pager "odoo-notify@*"
  else
    omitir "timers de systemd" "sin systemd"
  fi

  # --- Perfil restore ---
  # Nunca arrancan solos: son el único camino con escritura sobre pgdata y filestore.

  local vivos
  vivos=$(docker compose ps --format '{{.Service}}' 2>/dev/null | grep -c '^restore-')
  if [ "${vivos:-0}" -eq 0 ]; then ok "ningún contenedor de restore corriendo"
  else bad "ningún contenedor de restore corriendo" "$vivos vivos — make restore-down"; fi
}

# =====================================================================
# observability — prometheus, loki, grafana, alloy
# =====================================================================

v_observability() {
  titulo "observability"

  # Ídem backups: solo producción observa. Sin Prometheus no hay nada que preguntar.

  if ! declarado prometheus; then
    omitir "capa de observabilidad" "no está en este stack — es exclusiva de producción"
    return
  fi

  sano prometheus; sano loki; sano grafana; sano alloy

  # --- Targets ---
  # La topología híbrida exige que el propio Alloy sea un target: si no, su caída no alerta.

  local salida caidos
  if ! corriendo prometheus; then
    omitir "todos los targets de Prometheus up" "prometheus no está corriendo"
  elif ! salida=$(docker compose exec -T prometheus wget -qO- \
       'http://127.0.0.1:9090/api/v1/targets?state=any' 2>/dev/null) || [ -z "$salida" ]; then
    bad "todos los targets de Prometheus up" "no se pudo consultar la API de targets"
  else
    caidos=$(printf '%s' "$salida" | grep -o '"health":"down"' | wc -l | tr -d ' ')
    if [ "$caidos" -eq 0 ]; then ok "todos los targets de Prometheus up"
    else bad "todos los targets de Prometheus up" "$caidos caídos — ver /targets en Grafana"; fi
  fi

  # --- Las tres familias que empuja Alloy ---
  # Host, contenedores y base: si falta una, el agente perdió un colector.

  local m
  for m in node_memory_MemAvailable_bytes container_memory_usage_bytes pg_up; do
    if docker compose exec -T prometheus wget -qO- \
         "http://127.0.0.1:9090/api/v1/query?query=count($m)" 2>/dev/null | grep -q '"value"'; then
      ok "métrica $m presente"
    else
      bad "métrica $m presente" "sin series — Alloy no está empujando esa familia"
    fi
  done

  # --- Logs ---

  expect "Loki recibe logs por contenedor" "odoo" docker compose exec -T prometheus \
    wget -qO- 'http://loki:3100/loki/api/v1/label/container/values'

  # --- Reglas de alerting realmente cargadas ---
  # Se cuentan contra el archivo, no se asume que cargó. Un fallo de provisioning
  # completo NO es silencioso —Grafana sale con código 1 y entra en loop, y eso lo
  # atrapa `sano grafana`—, pero una regla que no provisiona sí lo es: el resto
  # carga, el stack se ve sano, y esa alerta no dispara nunca.

  local esperadas cargadas codigo pass_gf
  esperadas=$(grep -c '^      - uid:' config/grafana/provisioning/alerting/rules.yaml)
  if [ "${esperadas:-0}" -eq 0 ]; then
    bad "reglas de alerting cargadas" \
        "no se pudo contar ninguna en rules.yaml — el chequeo no verifica nada hasta arreglar el conteo"
  elif ! corriendo grafana; then
    omitir "las $esperadas reglas de alerting cargadas" "grafana no está corriendo"
  # El secret es 640 root:472 y el operador no está en ese grupo: desde el host es
  # ilegible siempre. Adentro sí, que corre 472:0 con el 472 como suplementario.
  elif ! pass_gf=$(docker compose exec -T grafana cat /run/secrets/grafana_admin_password 2>/dev/null | tr -d '\r\n') || [ -z "$pass_gf" ]; then
    omitir "las $esperadas reglas de alerting cargadas" "no se pudo leer el secret desde el contenedor"
  else
    codigo=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -u "admin:$pass_gf" \
      http://127.0.0.1:3001/api/v1/provisioning/alert-rules 2>/dev/null)
    if [ "$codigo" != "200" ]; then
      omitir "las $esperadas reglas de alerting cargadas" "la API respondió $codigo, no 200"
    else
      cargadas=$(curl -s -m 10 -u "admin:$pass_gf" \
        http://127.0.0.1:3001/api/v1/provisioning/alert-rules 2>/dev/null \
        | grep -o '"uid":' | wc -l | tr -d ' ')
      if [ "${cargadas:-0}" -ge "$esperadas" ]; then
        ok "las $esperadas reglas de alerting cargadas"
      else
        bad "las $esperadas reglas de alerting cargadas" \
            "solo ${cargadas:-0} — hay reglas que no provisionaron y no van a disparar nunca"
      fi
    fi
  fi

  # --- Los dos umbrales de frescura del backup ---
  # La alerta tiene que avisar ANTES de que el healthcheck marque unhealthy. Los dos
  # derivan de la cadencia del timer y viven en archivos de herramientas distintas.

  local alerta maxage
  alerta=$(sed -n 's/.*params: \[\([0-9]\{4,\}\)\].*/\1/p' \
           config/grafana/provisioning/alerting/rules.yaml | head -1)
  maxage="${RESTIC_MAX_AGE:-129600}"
  if [ -z "$alerta" ]; then
    aviso "la alerta de backup avisa antes que el healthcheck" "no se pudo leer el umbral"
  elif [ "$alerta" -le "$maxage" ]; then
    ok "la alerta de backup ($((alerta/3600)) h) avisa antes que el healthcheck ($((maxage/3600)) h)"
  else
    bad "la alerta de backup avisa antes que el healthcheck" \
        "alerta $((alerta/3600)) h > healthcheck $((maxage/3600)) h — el contenedor se pone rojo primero"
  fi

  # --- Rotación de logs del daemon ---
  # Solo aplica a contenedores creados después del restart de dockerd.

  local cid
  cid=$(docker compose ps -q odoo 2>/dev/null)
  if [ -z "$cid" ]; then
    bad "rotación de logs aplicada" "odoo no está corriendo, no se puede comprobar"
  else
    expect "rotación de logs aplicada" "max-size" \
      docker inspect "$cid" --format '{{json .HostConfig.LogConfig}}'
  fi

  # --- Binds ---
  # Solo Grafana publica, y en loopback: se entra por túnel SSH.

  sin_publicar prometheus 9090
  sin_publicar loki 3100
  sin_publicar alloy 12345
  bind_es grafana 3000
}

# --- Resumen ---
# El exit code es lo que consume el operador: 0 = la capa está sana.

resumen() {
  local linea="$PASS ok · $FALLO fallas · $AVISO avisos"
  if [ "$FALLO" -eq 0 ]; then printf '\n%s✓%s %s\n' "$UI_GREEN" "$UI_RESET" "$linea"
  else printf '\n%s✗%s %s\n' "$UI_RED" "$UI_RESET" "$linea"; fi
  [ "$FALLO" -eq 0 ]
}

# --- Sourceado desde los tests ---
# Sin esto, importar los helpers correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

case "${1:-all}" in
  host)          v_host ;;
  edge)          v_edge ;;
  db)            v_db ;;
  odoo)          v_odoo ;;
  backups)       v_backups ;;
  observability) v_observability ;;
  all)           v_host; v_edge; v_db; v_odoo; v_backups; v_observability ;;
  *) echo "uso: $(basename "$0") [host|edge|db|odoo|backups|observability|all]" >&2; exit 2 ;;
esac

resumen
