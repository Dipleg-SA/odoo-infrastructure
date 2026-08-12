#!/usr/bin/env bash
# Verificación del deploy, una capa por subcomando. Dueño único de qué se chequea
# y de qué se espera: INSTALL.md nombra el comando, los valores viven acá.

# Sin -e a propósito: un verificador que aborta en el primer fallo esconde el resto
# del diagnóstico, que es justo para lo que se lo corre.
set -uo pipefail

cd "$(dirname "$0")/.."

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

ok()     { printf '  ok      %s\n' "$1"; PASS=$((PASS+1)); }
bad()    { printf '  FALLA   %s\n            %s\n' "$1" "$2"; FALLO=$((FALLO+1)); }
aviso()  { printf '  aviso   %s\n            %s\n' "$1" "$2"; AVISO=$((AVISO+1)); }
omitir() { printf '  --      %s (%s)\n' "$1" "$2"; }
titulo() { printf '\n%s\n' "$1"; }

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

# --- ¿El servicio está levantado? ---
# Un chequeo de runtime contra un servicio apagado no puede concluir nada: dar ok
# seria mentir y dar FALLA seria culpar al chequeo equivocado. Se omite.

corriendo() { [ -n "$(docker compose ps -q "$1" 2>/dev/null)" ]; }

# --- Búsqueda en logs ---
# Helper propio porque vacio() no puede llevar un pipe: acá el grep es parte del chequeo.

log_limpio() {
  local nombre="$1" patron="$2"; shift 2
  local salida
  if ! corriendo "$1"; then omitir "$nombre" "$1 no está corriendo"; return; fi
  salida=$(docker compose logs --tail 500 --no-log-prefix "$@" 2>/dev/null | grep -iE "$patron")
  if [ -z "$salida" ]; then ok "$nombre"
  else bad "$nombre" "$(printf '%s' "$salida" | head -1)"; fi
}

# --- Estado de un servicio ---
# Distingue "no levantado" de "unhealthy": el primero es una capa que falta, el segundo un fallo.

sano() {
  local svc="$1" estado
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

bind_es() {
  local svc="$1" puerto="$2" esperado="$3" actual
  if ! corriendo "$svc"; then omitir "$svc:$puerto publicado en $esperado" "$svc no está corriendo"; return; fi
  if ! actual=$(publicado_en "$svc" "$puerto"); then
    bad "$svc:$puerto publicado en $esperado" "no está publicado"; return
  fi
  if [ "$actual" = "$esperado" ]; then ok "$svc:$puerto publicado en $esperado"
  else bad "$svc:$puerto publicado en $esperado" "está en $actual — viola el criterio de bind"; fi
}

sin_publicar() {
  local svc="$1" puerto="$2" actual
  if ! corriendo "$svc"; then omitir "$svc:$puerto sin publicar" "$svc no está corriendo"; return; fi
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
  # La directiva include: de compose.yaml exige v2.20 o superior.

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
  if [ ! -f .env ]; then bad ".env presente" "no existe — cp .env.example .env"
  elif [ -n "$vacias" ]; then bad ".env sin claves vacías" "vacías: $vacias"
  else ok ".env sin claves vacías"; fi

  # --- Secrets ---
  # Delegado: scripts/secrets-perms.sh es el dueño único del mapa de GIDs.

  if scripts/secrets-perms.sh --check >/dev/null 2>&1; then
    ok "secrets con permisos, grupo y valor cargado"
  else
    bad "secrets con permisos, grupo y valor cargado" "correr: scripts/secrets-perms.sh --check"
  fi

  # --- acme.json ---
  # Si Docker lo creó como directorio, Traefik nunca persiste el certificado.

  if [ -d config/traefik/acme.json ]; then
    bad "acme.json es archivo" "es un DIRECTORIO — Traefik reemite hasta chocar el rate-limit de LE"
  elif [ -f config/traefik/acme.json ]; then
    ok "acme.json es archivo"
  else
    bad "acme.json es archivo" "no existe — correr make config-init"
  fi

  # --- ufw ---
  # Solo gobierna puertos de procesos del host; acá el 53/udp de dnsmasq.

  if command -v ufw >/dev/null 2>&1; then
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
  else aviso "ningún contenedor publica en 0.0.0.0" "expuestos: $expuestos "; fi
}

# =====================================================================
# edge — traefik, cloudflared, dnsmasq
# =====================================================================

v_edge() {
  titulo "edge"

  sano traefik; sano cloudflared; sano dnsmasq

  # --- Resolver de la LAN ---
  # El healthcheck de dnsmasq le pregunta a él: prueba que responde, no que se lo consulte.

  omitir "la LAN usa dnsmasq como resolver" \
    "no verificable desde el servidor — correr el chequeo 3b de INSTALL.md en un equipo de la LAN"

  # --- Config estática de Traefik ---
  # Un caServer de staging emite un cert que cloudflared rechaza: el sitio entero queda en 502.

  vacio "traefik.yaml sin email ni caServer" grep -E '^[[:space:]]*(email|caServer):' config/traefik/traefik.yaml

  # --- Túnel ---
  # Cuatro conexiones registradas es lo normal; una sola funciona pero está degradado.

  local conns
  conns=$(docker compose logs cloudflared 2>/dev/null | grep -c "Registered tunnel connection")
  if [ "${conns:-0}" -ge 2 ]; then ok "cloudflared con $conns conexiones registradas"
  elif [ "${conns:-0}" -eq 1 ]; then aviso "cloudflared con >=2 conexiones" "solo 1 — degradado"
  else bad "cloudflared con >=2 conexiones" "0 — el Tunnel no conecta"; fi

  log_limpio "traefik sin errores en el log" 'level=error|level=fatal' traefik

  # --- Dashboard ---
  # Sin auth propia: su aislamiento es el bind a loopback, no una credencial.

  expect "dashboard de Traefik responde" "200" \
    curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:8080/api/rawdata

  # --- Binds ---
  # Nivel 3 (LAN) para 80/443, nivel 2 (loopback) para el dashboard.

  if [ -n "$LOCAL_IP" ]; then
    bind_es traefik 80 "$LOCAL_IP"
    bind_es traefik 443 "$LOCAL_IP"
  else
    omitir "binds de traefik" "falta LOCAL_IP en .env"
  fi
  bind_es traefik 8080 127.0.0.1

  # --- Token de Cloudflare ---
  # Valor y alcance de una sola vez, contra la API real. Un token inválido no se
  # manifiesta hasta la capa de Odoo, y ahí lo hace como un 502 que no lo menciona.

  local token resp
  if token=$(cat secrets/cloudflare_api_token 2>/dev/null) && [ -n "$token" ]; then
    resp=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/user/tokens/verify"\n' \
      "$token" | curl -s -m 10 --config - 2>/dev/null)
    case "$resp" in
      *'"status":"active"'*) ok "token de Cloudflare activo" ;;
      *1000*) bad "token de Cloudflare activo" "1000 Invalid API Token — el valor está mal pegado" ;;
      *9109*) bad "token de Cloudflare activo" "9109 — el token no lee la zona; rehacerlo con la plantilla Edit zone DNS" ;;
      *) bad "token de Cloudflare activo" "respuesta inesperada de la API" ;;
    esac
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

  expect "archive_mode activo" "on" docker compose exec -T postgres \
    psql -U odoo -tAc "SHOW archive_mode"
  expect "archive_command hacia pgBackRest" "pgbackrest archive-push" \
    docker compose exec -T postgres psql -U odoo -tAc "SHOW archive_command"

  # --- Stanza ---
  # cipher confirma que el repo está cifrado; el rango de wal archive, que el
  # archive_command llega de verdad a R2 y no solo parsea.

  # --- Coherencia de la stanza ---
  # pgBackRest no interpola variables dentro de su config, así que el nombre de la
  # sección y PGBACKREST_STANZA se mantienen iguales a mano. Si divergen, se queda
  # sin pg1-path y el archivado muere sin que la config parezca rota.

  local stanza="${PGBACKREST_STANZA:-}"
  if [ -z "$stanza" ]; then
    bad "stanza declarada en .env" "PGBACKREST_STANZA vacío"
  elif grep -q "^\[$stanza\]" config/pgbackrest/pgbackrest.conf 2>/dev/null; then
    ok "stanza '$stanza' tiene su sección en pgbackrest.conf"
  else
    bad "stanza '$stanza' tiene su sección en pgbackrest.conf" \
        "no existe la sección [$stanza] — pgBackRest se queda sin pg1-path"
  fi

  # --- Coherencia de las dos retenciones ---
  # El techo de pgBackRest no es un número elegido: tiene que cubrir la ventana de
  # restic, o un restore de la base se queda sin filestore de esa fecha. Los dos
  # valores viven en archivos de herramientas distintas y nada más los ata.

  local dia sem mes cobertura ret
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

  # --- process-max contra los cpus del contenedor ---
  # Si supera el cap, pgBackRest compite con la base durante el backup.

  local pmax pcpus
  pmax=$(sed -n 's/^process-max[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' \
         config/pgbackrest/pgbackrest.conf | head -1)
  pcpus=$(sed -n '/^  postgres:/,/^  [a-z]/p' compose.db.yaml | sed -n 's/.*cpus: "\([0-9.]*\)".*/\1/p' | head -1)
  if [ -z "$pmax" ] || [ -z "$pcpus" ]; then
    aviso "process-max dentro de los cpus de postgres" "no se pudieron leer los valores"
  elif awk -v a="$pmax" -v b="$pcpus" 'BEGIN{exit !(a<=b)}'; then
    ok "process-max ($pmax) dentro de los cpus de postgres ($pcpus)"
  else
    bad "process-max dentro de los cpus de postgres" \
        "process-max $pmax > cpus $pcpus — pgBackRest compite con la base"
  fi

  expect "stanza cifrada en R2" "aes-256-cbc" \
    docker compose exec -T -u postgres postgres pgbackrest info

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
    bad "worktrees de producción presentes" "árbol vacío — correr make addons-sync"
  elif [ -n "$faltan" ]; then
    bad "worktrees de producción presentes" "sin clonar: $faltan — correr make addons-sync"
  elif [ -n "$sucios" ]; then
    bad "worktrees de producción limpios" "sucios: $sucios — addons.sh no actualiza un worktree con cambios"
  else
    ok "worktrees de producción presentes y limpios"
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

  # --- Routers ---
  # Los tres: raíz, websocket al worker gevent, y el de rate-limit del login.

  local routers
  routers=$(curl -s -m 5 http://127.0.0.1:8080/api/http/routers 2>/dev/null | grep -o '"name":"odoo[^"]*"' | wc -l | tr -d ' ')
  if [ "${routers:-0}" -ge 3 ]; then ok "los 3 routers de Odoo en Traefik"
  else bad "los 3 routers de Odoo en Traefik" "hay $routers — faltan labels o Traefik no los descubrió"; fi

  # --- Certificado ---
  # Uno de staging hace que cloudflared rechace el origen y todo el sitio dé 502.

  if [ -z "$PUBLIC_HOSTNAME" ]; then
    omitir "certificado de producción" "falta PUBLIC_HOSTNAME en .env"
  else
    local cert
    cert=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$PUBLIC_HOSTNAME" 2>/dev/null \
      | openssl x509 -noout -issuer -subject -enddate 2>/dev/null)
    case "$cert" in
      "") bad "certificado de producción" "no se pudo leer el certificado del :443" ;;
      *"(STAGING)"*) bad "certificado de producción" "es de la CA de staging — sacar caServer y borrar acme.json" ;;
      *"Let's Encrypt"*)
        if echo | openssl s_client -connect 127.0.0.1:443 -servername "$PUBLIC_HOSTNAME" 2>/dev/null \
           | openssl x509 -noout -checkend $((21*86400)) >/dev/null 2>&1; then
          ok "certificado de Let's Encrypt, vence en más de 21 días"
        else
          bad "certificado vigente" "vence en menos de 21 días — la renovación automática no corrió"
        fi ;;
      *) bad "certificado de producción" "emisor inesperado; ¿sigue sirviendo TRAEFIK DEFAULT CERT?" ;;
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

  sano backup

  expect "repo de restic con snapshots" "odoo-prod" \
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
    expect "aviso de fallo cableado" "odoo-backup-notify" \
      systemctl cat odoo-backup-daily.service
    expect "unit plantilla de aviso instalada" "odoo-backup-notify@" \
      systemctl list-unit-files --no-pager "odoo-backup-notify@*"
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
  bind_es grafana 3000 127.0.0.1
}

# --- Resumen ---
# El exit code es lo que consume el operador: 0 = la capa está sana.

resumen() {
  printf '\n%s ok · %s fallas · %s avisos\n' "$PASS" "$FALLO" "$AVISO"
  [ "$FALLO" -eq 0 ]
}

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
