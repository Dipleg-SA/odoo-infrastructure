#!/usr/bin/env bash
# Los derivadores de verify.sh: las funciones que deciden si un chequeo se corre,
# se omite o falla. Ahí vive la diferencia entre "esta capa no está en este stack"
# y "este servicio se cayó", que es lo que hace que la salida se pueda creer.
#
# verify.sh se sourcea ANTES que lib.sh a propósito: los dos definen ok/bad/titulo,
# y así el arnés gana y el reporte sale con el formato de los tests.

cd "$(dirname "$0")/.."

STUB_DIR=$(mktemp -d); export STUB_DIR
trap 'rm -rf "$STUB_DIR"' EXIT
PATH="$PWD/tests/stubs:$PATH"

. scripts/verify.sh
. tests/lib.sh

config_fixture() { cat > "$STUB_DIR/config"; }
puerto_fixture() { printf '%s\n' "$1" > "$STUB_DIR/port"; }

# =====================================================================
titulo "declarado — qué capas trae este stack"
# =====================================================================

SERVICIOS=$'nginx\nodoo\npostgres\npgbouncer'

igual "reconoce un servicio del stack"        "0" "$(declarado nginx; echo $?)"
igual "y rechaza uno que no incluye"          "1" "$(declarado backup; echo $?)"
igual "sin coincidencia parcial"              "1" "$(declarado ngin; echo $?)"

# El daemon caído es lo que la capa host existe para diagnosticar: si acá dijera
# que no, verify omitiría el stack entero y daría verde sobre nada.
SERVICIOS=""
igual "sin composición legible responde que sí a todo" "0" "$(declarado backup; echo $?)"

# =====================================================================
titulo "motivo — por qué se omite"
# =====================================================================

SERVICIOS=$'nginx\nodoo'
igual "un servicio declarado y abajo está caído"   "nginx no está corriendo"    "$(motivo nginx)"
igual "uno ausente es una capa que no lleva"       "backup no está en este stack" "$(motivo backup)"

# =====================================================================
titulo "publicado_en — el 'invalid IP:0' que no es vacío"
# =====================================================================

puerto_fixture "10.0.0.2:443"
igual "devuelve la IP publicada" "10.0.0.2" "$(publicado_en nginx 443)"

# docker compose port imprime esto, con exit 0, para un puerto NO publicado.
# Tomarlo como publicado marcaría en rojo todos los puertos internos.
puerto_fixture "invalid IP:0"
igual "trata 'invalid IP:0' como no publicado" "1" "$(publicado_en postgres 5432 >/dev/null; echo $?)"

puerto_fixture ""
igual "y la salida vacía también" "1" "$(publicado_en postgres 5432 >/dev/null; echo $?)"

puerto_fixture "0.0.0.0:80"
igual "no disimula un 0.0.0.0" "0.0.0.0" "$(publicado_en nginx 80)"

# =====================================================================
titulo "bind_declarado — la IP esperada sale de la composición"
# =====================================================================

config_fixture <<'EOF'
name: test
services:
  nginx:
    container_name: test-nginx
    ports:
      - mode: ingress
        host_ip: 10.0.0.2
        target: 80
        published: "80"
        protocol: tcp
      - mode: ingress
        host_ip: 10.0.0.2
        target: 443
        published: "443"
        protocol: tcp
  odoo:
    container_name: test-odoo
networks:
  app: null
EOF

igual "lee la IP del puerto publicado" "10.0.0.2" "$(bind_declarado nginx 443)"
igual "un puerto que el stack no publica devuelve 1" "1" "$(bind_declarado nginx 8069 >/dev/null; echo $?)"

# El ancla del $ importa: sin ella "target: 80" matchea "target: 8069".
config_fixture <<'EOF'
services:
  odoo:
    ports:
      - mode: ingress
        host_ip: 127.0.0.1
        target: 8069
        published: "8069"
networks:
  app: null
EOF
igual "no confunde el 8069 con el 80" "1" "$(bind_declarado odoo 80 >/dev/null; echo $?)"

# Un ports: sin IP no emite host_ip, y eso ES un 0.0.0.0.
config_fixture <<'EOF'
services:
  nginx:
    ports:
      - mode: ingress
        target: 80
        published: "80"
networks:
  app: null
EOF
igual "un puerto sin host_ip es 0.0.0.0" "0.0.0.0" "$(bind_declarado nginx 80)"

# Falla abierta, igual que declarado: el chequeo reporta su propio fallo.
: > "$STUB_DIR/config"
igual "sin composición legible devuelve '?'" "?" "$(bind_declarado nginx 80)"

# =====================================================================
titulo "modo_plain — el modo del proxy sale de la plantilla montada"
# =====================================================================

config_fixture <<'EOF'
services:
  nginx:
    volumes:
      - type: bind
        source: /repo/config/nginx/server-plain.conf.template
        target: /etc/nginx/templates/default.conf.template
EOF
igual "detecta el stack sin TLS" "0" "$(modo_plain; echo $?)"

config_fixture <<'EOF'
services:
  nginx:
    volumes:
      - type: bind
        source: /repo/config/nginx/server-tls.conf.template
        target: /etc/nginx/templates/default.conf.template
EOF
igual "y el que sí lo termina" "1" "$(modo_plain; echo $?)"

# NGINX_MODE no participa: development no la declara y el modo se sabe igual.
export NGINX_MODE=plain
igual "no lo decide la variable de entorno" "1" "$(modo_plain; echo $?)"
unset NGINX_MODE

# =====================================================================
titulo "sano — una capa ausente se omite, no se marca en rojo"
# =====================================================================

SERVICIOS=$'nginx\nodoo'
contiene "nombra que no está en este stack" "backup levantado (no está en este stack)" "$(sano backup 2>&1)"

# =====================================================================
titulo "rotacion_aplicada — el daemon.json del host lleva el límite"
# =====================================================================

DAEMON_JSON="$STUB_DIR/daemon.json"; export DAEMON_JSON

# El contrato es "pasa o falla", no el código exacto: grep sale 2 con el archivo
# ausente y 1 sin match, y el llamador solo lo usa como condición de un if.
veredicto() { if rotacion_aplicada; then echo pasa; else echo falla; fi; }

cp config/docker/daemon.json "$DAEMON_JSON"
igual "el archivo del repo pasa"           "pasa"  "$(veredicto)"

# El caso caro: el daemon por defecto usa json-file igual, pero sin cap. Verlo
# recién con el stack arriba obliga a recrear los once contenedores.
echo '{}' > "$DAEMON_JSON"
igual "un daemon.json sin límite falla"    "falla" "$(veredicto)"

# Claves ajenas al repo son legítimas; lo que se exige es el cap, no el archivo entero.
printf '{"data-root":"/mnt/docker","log-opts":{"max-size":"10m"}}\n' > "$DAEMON_JSON"
igual "y con claves propias del host pasa" "pasa"  "$(veredicto)"

rm -f "$DAEMON_JSON"
igual "sin archivo también falla"          "falla" "$(veredicto)"

# =====================================================================
titulo "timer_activo — la unit sale de timers.sh, no de una lista de acá"
# =====================================================================

# El nombre no se afirma literal: se le pregunta al mismo dueño al que verify.sh
# le pregunta. Lo que se afirma es que no lo inventa y que no recorta la salida.

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-production}"
printf 'postgres\nodoo\nbackup\ncertbot\n' > "$STUB_DIR/servicios"

UNIDAD=$(scripts/timers.sh units | grep -- '-backup-daily$')
{ scripts/timers.sh units | sed 's/$/.timer activa/'
  printf 'OnFailure=%s%%n.service\n' "$(scripts/timers.sh notify)"; } > "$STUB_DIR/systemctl"

: > "$STUB_DIR/llamadas"
contiene "chequea la unit prefijada que nombra timers.sh" \
  "timer backup-daily activo ($UNIDAD.timer)" "$(timer_activo backup-daily 2>&1)"

# Sin --full systemd asume 80 columnas y elide el nombre: el chequeo daría rojo en verde.
contiene "y pide --full para que el nombre no se recorte" \
  "list-timers --all --full" "$(cat "$STUB_DIR/llamadas")"

# La plantilla es una sola por stack: el latch evita repetir el chequeo en cada timer.
SALIDA=$( { timer_activo backup-daily; timer_activo backup-monthly; } 2>&1 )
igual "la plantilla de aviso se chequea una sola vez" "1" \
  "$(printf '%s\n' "$SALIDA" | grep -c 'unit plantilla de aviso instalada')"

# Un stack sin certbot no tiene esa unit: omitida, no marcada en rojo.
printf 'postgres\nodoo\n' > "$STUB_DIR/servicios"
contiene "sin la capa, se omite en vez de fallar" \
  "no corresponde a este stack" "$(timer_activo cert-renew 2>&1)"

resumen
