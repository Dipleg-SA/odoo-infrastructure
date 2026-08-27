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

. scripts/lib/verify.sh
. tests/lib.sh

config_fixture() { cat > "$STUB_DIR/config"; }
puerto_fixture() { printf '%s\n' "$1" > "$STUB_DIR/port"; }

# =====================================================================
titulo "declarado — qué capas trae este stack"
# =====================================================================

SERVICIOS=$'nginx\nodoo\npostgres\nbackup'

igual "reconoce un servicio del stack"        "0" "$(declarado nginx; echo $?)"
igual "y rechaza uno que no incluye"          "1" "$(declarado grafana; echo $?)"
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

# Las rutas son las que emite `docker compose config` de verdad: archivos reales
# bajo stacks/nginx/config/, sin .template — si el fixture usa el nombre viejo, el
# test pasa con un modo_plain que no matchea nada en el stack real.

config_fixture <<'EOF'
services:
  nginx:
    volumes:
      - type: bind
        source: /repo/stacks/nginx/config/server-plain.conf
        target: /etc/nginx/conf.d/default.conf
EOF
igual "detecta el stack sin TLS" "0" "$(modo_plain; echo $?)"

config_fixture <<'EOF'
services:
  nginx:
    volumes:
      - type: bind
        source: /repo/stacks/nginx/config/server-tls.conf
        target: /etc/nginx/conf.d/default.conf
EOF
igual "y el que sí lo termina" "1" "$(modo_plain; echo $?)"

# El nombre viejo ya no monta nadie: si vuelve a matchear, el patrón quedó laxo.
config_fixture <<'EOF'
services:
  nginx:
    volumes:
      - type: bind
        source: /repo/config/nginx/server-plain.conf.template
        target: /etc/nginx/templates/default.conf.template
EOF
igual "no matchea la plantilla envsubst que ya no existe" "1" "$(modo_plain; echo $?)"

# NGINX_MODE no participa: development no la declara y el modo se sabe igual.
config_fixture <<'EOF'
services:
  nginx:
    volumes:
      - type: bind
        source: /repo/stacks/nginx/config/server-tls.conf
        target: /etc/nginx/conf.d/default.conf
EOF
export NGINX_MODE=plain
igual "no lo decide la variable de entorno" "1" "$(modo_plain; echo $?)"
unset NGINX_MODE

# =====================================================================
titulo "smtp_activo — quién usa de verdad el smtp_server de odoo.conf"
# =====================================================================

config_fixture <<'EOF'
services:
  odoo:
    environment:
      HOST: postgres
EOF
igual "producción manda correo" "0" "$(smtp_activo; echo $?)"

config_fixture <<'EOF'
services:
  odoo:
    environment:
      ODOO_DISABLE_SMTP: "1"
EOF
igual "staging y development no" "1" "$(smtp_activo; echo $?)"

# =====================================================================
titulo "sin_placeholder — el .example sin editar, y el bootstrap sin hacer"
# =====================================================================

printf 'smtp_server = mail.ejemplo.net\n' > "$STUB_DIR/editado.conf"
printf 'smtp_server = TU_SMTP_HOST\n'     > "$STUB_DIR/crudo.conf"

contiene "un config editado pasa" "  ok" \
  "$(sin_placeholder "x" "$STUB_DIR/editado.conf" 'TU_SMTP_HOST|TU_SMTP_PORT')"

contiene "uno con el placeholder falla" "FALLA" \
  "$(sin_placeholder "x" "$STUB_DIR/crudo.conf" 'TU_SMTP_HOST|TU_SMTP_PORT')"

contiene "y nombra cuál quedó" "TU_SMTP_HOST" \
  "$(sin_placeholder "x" "$STUB_DIR/crudo.conf" 'TU_SMTP_HOST|TU_SMTP_PORT')"

# El .example de cada herramienta dice "Reemplazá TU_X por..." en un comentario que
# sigue ahí después de haber cargado el valor. Sin descartar comentarios, el chequeo
# no podía pasar NUNCA por más que el operador hiciera todo bien — se descubrió con
# grafana.ini, cuyos valores estaban todos completos y el chequeo seguía en rojo.

printf '; Reemplaza TU_SMTP_HOST por el host real\nsmtp_server = mail.ejemplo.net\n' > "$STUB_DIR/comentado.conf"
printf '# Reemplaza TU_SMTP_HOST\nsmtp_server = TU_SMTP_HOST\n'                      > "$STUB_DIR/mixto.conf"
printf '// Reemplaza TU_SMTP_HOST\nsmtp_server = mail.ejemplo.net\n'                 > "$STUB_DIR/alloy.conf"

contiene "el placeholder en un comentario no cuenta" "  ok" \
  "$(sin_placeholder "x" "$STUB_DIR/comentado.conf" 'TU_SMTP_HOST')"

contiene "ni con el comentario de config.alloy" "  ok" \
  "$(sin_placeholder "x" "$STUB_DIR/alloy.conf" 'TU_SMTP_HOST')"

# La otra mitad: descartar comentarios no puede tapar un valor sin cargar.
contiene "pero en un valor sigue fallando" "FALLA" \
  "$(sin_placeholder "x" "$STUB_DIR/mixto.conf" 'TU_SMTP_HOST')"

# El archivo ausente es el bootstrap sin hacer: un grep que no matchea daría verde
# justo donde el chequeo existe para atrapar eso, y Compose montaría un directorio.

contiene "el archivo ausente falla, no da verde" "FALLA" \
  "$(sin_placeholder "x" "$STUB_DIR/no-existe.conf" 'TU_SMTP_HOST')"

no_contiene "y no lo reporta como ok" "  ok" \
  "$(sin_placeholder "x" "$STUB_DIR/no-existe.conf" 'TU_SMTP_HOST')"

# =====================================================================
titulo "claves_ausentes — una clave que nunca se escribió, no solo vacía"
# =====================================================================

# Escenario real: ALERT_EMAIL_FROM nunca se escribió en .env.production.example
# (no 'ALERT_EMAIL_FROM=', directamente no estaba la línea), así que ningún grep de
# '^KEY=$' lo atrapaba — host-verify daba verde y notify-test fallaba en el
# servidor meses después, con el aviso de fallo que se supone que manda ese mismo
# mecanismo.

printf 'COMPOSE_PROJECT_NAME=production\nPUBLIC_HOSTNAME=\nSMTP_HOST=\nSMTP_USER=\nALERT_EMAIL_FROM=\nALERT_EMAIL_TO=\n#COMPOSE_PROFILES=lan\n' \
  > "$STUB_DIR/plantilla.example"

printf 'COMPOSE_PROJECT_NAME=production\nPUBLIC_HOSTNAME=odoo.ejemplo.com\nSMTP_HOST=smtp.ejemplo.com\nSMTP_USER=apikey\nALERT_EMAIL_TO=ops@ejemplo.com\n' \
  > "$STUB_DIR/env-incompleto"

igual "la clave nunca escrita se reporta" "ALERT_EMAIL_FROM" \
  "$(claves_ausentes "$STUB_DIR/plantilla.example" "$STUB_DIR/env-incompleto")"

printf 'ALERT_EMAIL_FROM=alertas@ejemplo.com\n' >> "$STUB_DIR/env-incompleto"

igual "completa la clave y no falta ninguna" "" \
  "$(claves_ausentes "$STUB_DIR/plantilla.example" "$STUB_DIR/env-incompleto")"

# Una clave presente pero vacía la sigue atrapando el grep de '^KEY=$' de al lado,
# no este helper: claves_ausentes exige valor, así que también la marca —
# redundante con esa otra rama, pero no un falso verde.

printf 'COMPOSE_PROJECT_NAME=production\nSMTP_USER=\n' > "$STUB_DIR/env-vacio"
igual "una clave presente pero vacía también cuenta como ausente acá" "1" \
  "$(claves_ausentes "$STUB_DIR/plantilla.example" "$STUB_DIR/env-vacio" | grep -cw SMTP_USER)"

# Una clave que la plantilla nunca declaró — comentada, opcional de verdad — no
# se exige: distinto de una que sí está pero no se completó.

igual "una clave comentada en la plantilla no se exige" "0" \
  "$(claves_ausentes "$STUB_DIR/plantilla.example" "$STUB_DIR/env-incompleto" | grep -c COMPOSE_PROFILES)"

igual "sin plantilla, devuelve error en vez de mentir" "1" \
  "$(claves_ausentes "$STUB_DIR/no-existe.example" "$STUB_DIR/env-incompleto" >/dev/null; echo $?)"

# =====================================================================
titulo "sano — una capa ausente se omite, no se marca en rojo"
# =====================================================================

SERVICIOS=$'nginx\nodoo'
contiene "nombra que no está en este stack" "backup levantado (no está en este stack)" "$(sano backup 2>&1)"

# =====================================================================
titulo "log_limpio — el error por diseño no cuenta, el resto sí"
# =====================================================================

# nginx loguea "could not be resolved" cada vez que llega un request y Odoo no está:
# es la contracara del resolver, y sobre el log entero no se va nunca más.

SERVICIOS=$'nginx\nodoo'
printf 'test-nginx\n' > "$STUB_DIR/ps-q"

: > "$STUB_DIR/salida"
contiene "un log limpio pasa" "ok      nginx sin errores" \
  "$(log_limpio "nginx sin errores" '\[error\]' 'could not be resolved' nginx 2>&1)"

printf '2026/08/24 [error] odoo could not be resolved (2: Server failure)\n' > "$STUB_DIR/salida"
contiene "la línea exceptuada no falla" "ok      nginx sin errores" \
  "$(log_limpio "nginx sin errores" '\[error\]' 'could not be resolved' nginx 2>&1)"

# Que el ok de arriba sea por la excepción y no porque el chequeo dejó de mirar:
# la misma línea, sin excepción, tiene que fallar.
contiene "y sin excepción sí falla" "FALLA   nginx sin errores" \
  "$(log_limpio "nginx sin errores" '\[error\]' "" nginx 2>&1)"

printf '2026/08/24 [emerg] bind() to 0.0.0.0:443 failed\n' > "$STUB_DIR/salida"
contiene "cualquier otro error sigue fallando" "FALLA   nginx sin errores" \
  "$(log_limpio "nginx sin errores" '\[error\]|\[emerg\]' 'could not be resolved' nginx 2>&1)"

: > "$STUB_DIR/salida"; rm -f "$STUB_DIR/ps-q"

# =====================================================================
titulo "rotacion_aplicada — el daemon.json del host lleva el límite"
# =====================================================================

DAEMON_JSON="$STUB_DIR/daemon.json"; export DAEMON_JSON

# El contrato es "pasa o falla", no el código exacto: grep sale 2 con el archivo
# ausente y 1 sin match, y el llamador solo lo usa como condición de un if.
veredicto() { if rotacion_aplicada; then echo pasa; else echo falla; fi; }

cp host/daemon.json "$DAEMON_JSON"
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

# =====================================================================
titulo "alloy_salud — el parser que decide si un componente dejó de emitir"
# =====================================================================
# El único derivador que no vive en lib/: es de stacks/alloy/verify.sh, pero se
# ejercita igual que el resto porque el error que tuvo —un patrón sin anclar— no
# lo ve nadie hasta que Alloy se rompe de verdad y el chequeo igual da verde.

. stacks/alloy/verify.sh

SANOS='{"name":"a","health":{"state":"healthy"}},{"name":"b","health":{"state":"healthy"}}'
igual "cuenta los componentes y ninguno roto" "2 0" "$(alloy_salud "$SANOS")"

# 'healthy' suelto matchea DENTRO de "unhealthy": sin anclar el valor entero, este
# caso devolvía 0 rotos y el chequeo declaraba sano justo lo que existe para atrapar.
MIXTO='{"health":{"state":"healthy"}},{"health":{"state":"unhealthy"}},{"health":{"state":"exited"}}'
igual "un unhealthy cuenta como roto, igual que un exited" "3 2" "$(alloy_salud "$MIXTO")"

igual "un unhealthy solo no pasa por sano" "1 1" \
  "$(alloy_salud '{"health":{"state":"unhealthy"}}')"

# Grepear la clave equivocada daba cero coincidencias y el chequeo pasaba siempre:
# total en 0 es lo que hace que v_alloy falle en vez de dar verde sobre nada.
igual "una respuesta sin componentes no se disimula" "0 0" "$(alloy_salud '{"otra":"cosa"}')"

resumen
