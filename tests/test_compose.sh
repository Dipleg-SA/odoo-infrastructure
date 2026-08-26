#!/usr/bin/env bash
# Contrato de los tres entrypoints: qué stacks, qué secrets y qué publica cada uno.
# No levanta nada — todo sale de `docker compose config`, que es la única fuente
# que sabe qué resolvió cada stack después de los include:, !reset y !override.

cd "$(dirname "$0")/.."
. tests/lib.sh

# --- Valores del deployment ---
# De un fixture y no del .env del operador: --env-file gana sobre un .env presente,
# así que el resultado no depende de en qué máquina se corra.

resuelto() {
  local env="$1"; shift
  docker compose --env-file "tests/fixtures/$env" "$@" config 2>/dev/null
}

servicios() {
  local env="$1"; shift
  docker compose --env-file "tests/fixtures/$env" "$@" config --services 2>/dev/null | sort | tr '\n' ' '
}

# --- Extractores sobre la config resuelta ---
# El bloque de un servicio va de su clave hasta la siguiente al mismo nivel, igual
# que en verify.sh. Los dígitos importan: restic_r2_credentials no matchea [a-z_]+.
# El corte incluye las claves de nivel 0: el último servicio alfabético no tiene
# servicio siguiente y el bloque se desbordaría dentro de networks:.

contar_secrets() { sed -n '/^secrets:/,$p' | grep -cE '^  [a-z0-9_]+:$'; }
bloque()         { sed -nE "/^  $1:$/,/^[a-z]|^  [a-z0-9_-]+:$/p"; }
binds()          { grep -B1 -E 'target: (80|443)$' | sed -n 's/^ *host_ip: //p' | tr '\n' ' '; }

# =====================================================================
titulo "development — envs/development.yaml"
# =====================================================================

DEVN=$(resuelto env.development -f envs/development.yaml)

igual "resuelve sin error" "0" "$(docker compose --env-file tests/fixtures/env.development -f envs/development.yaml config -q >/dev/null 2>&1; echo $?)"
igual "declara 2 secrets" "2" "$(printf '%s\n' "$DEVN" | contar_secrets)"
igual "solo proxy, datos y aplicación" "nginx odoo postgres " "$(servicios env.development -f envs/development.yaml)"

# server-plain no escucha en el 443: publicarlo ataría un puerto para nada.
igual "publica solo el 80, en loopback" "127.0.0.1 " "$(printf '%s\n' "$DEVN" | bloque nginx | binds)"

contiene    "monta el config sin TLS" "server-plain.conf" "$(printf '%s\n' "$DEVN" | bloque nginx)"
no_contiene "y ninguna con TLS" "server-tls" "$DEVN"

# Sin pooler: la simplificación de esta etapa. Postgres y nginx sí buildean —
# cada stack tiene su Dockerfile aunque no le sume nada a la imagen oficial—,
# con el mismo tag por proyecto que ya usaba odoo.
no_contiene "sin pgbouncer" "pgbouncer" "$DEVN"
contiene "postgres construye con tag por proyecto" "local/postgres:test-development" "$(printf '%s\n' "$DEVN" | bloque postgres)"
contiene "nginx construye con tag por proyecto" "local/nginx:test-development" "$(printf '%s\n' "$DEVN" | bloque nginx)"

contiene "un odoo.conf clonado no alcanza para mandar correo" 'ODOO_DISABLE_SMTP: "1"' "$(printf '%s\n' "$DEVN" | bloque odoo)"

# =====================================================================
# =====================================================================
titulo "producción — envs/production.yaml"
# =====================================================================

PRODN=$(resuelto env.production --profile cert -f envs/production.yaml)

igual "resuelve sin error" "0" "$(docker compose --env-file tests/fixtures/env.production -f envs/production.yaml config -q >/dev/null 2>&1; echo $?)"
igual "declara 9 secrets" "9" "$(printf '%s\n' "$PRODN" | contar_secrets)"
igual "los diez stacks de producción" "alloy backup certbot cloudflared grafana loki nginx odoo postgres prometheus " \
  "$(servicios env.production --profile cert -f envs/production.yaml)"

# Es el caso base: sin bloque services:, nginx cae a su default de TLS y publica
# en la LAN. Si esto cambia, algún entorno le está imponiendo su excepción.
contiene "monta el config con TLS" "server-tls.conf" "$(printf '%s\n' "$PRODN" | bloque nginx)"
igual "publica en la IP de la LAN, no en loopback" "10.0.0.2 10.0.0.2 " \
  "$(printf '%s\n' "$PRODN" | bloque nginx | binds)"

# certbot escribe el certificado que nginx lee: el volumen lo declara el entorno,
# porque dos declaraciones divergentes del mismo recurso se fusionan en silencio.
contiene "certbot escribe el volumen del certificado" "letsencrypt" "$(printf '%s\n' "$PRODN" | bloque certbot)"

# --- El dump y el filestore, en el mismo snapshot ---
# La consistencia deja de ser un procedimiento —respaldar en orden— y pasa a ser
# una propiedad: postgres escribe el dump en un volumen que backup lee junto al
# filestore. Si estos dos mounts se separan, el snapshot deja de ser restaurable
# como unidad y nada más lo avisa.

contiene "postgres escribe el dump en el volumen compartido" "dumps" "$(printf '%s\n' "$PRODN" | bloque postgres)"
contiene "backup lo lee junto al filestore"                  "dumps" "$(printf '%s\n' "$PRODN" | bloque backup)"
contiene "y el filestore va rw: el mismo contenedor restaura" "odoo-data" "$(printf '%s\n' "$PRODN" | bloque backup)"

# --- Observabilidad: una sola UI publicada ---
# Grafana es el único de los cuatro con puerto, y en loopback (nivel 2: se entra
# por túnel SSH). Los otros tres se consultan por nombre dentro de su red — si
# alguno gana un ports:, queda una UI sin auth propia expuesta y nada lo avisa.

igual "grafana publica solo en loopback" "127.0.0.1 " \
  "$(printf '%s\n' "$PRODN" | bloque grafana | grep -B1 'target: 3000' | sed -n 's/^ *host_ip: //p' | tr '\n' ' ')"

for svc in prometheus loki alloy; do
  igual "$svc no publica ningún puerto" "" \
    "$(printf '%s\n' "$PRODN" | bloque "$svc" | sed -n 's/^ *published: //p' | tr '\n' ' ')"
done

# =====================================================================
titulo "prueba — envs/staging.yaml"
# =====================================================================

# Con los dos perfiles: Compose PODA los secrets de un servicio inactivo, así que
# preguntar solo por --profile cert contaría 4 en vez de los 6 que declara el
# entrypoint. Lo que se afirma acá es la declaración, no una activación puntual.
STGN=$(resuelto env.staging --profile cert --profile restore -f envs/staging.yaml)

igual "resuelve sin error" "0" "$(docker compose --env-file tests/fixtures/env.staging -f envs/staging.yaml config -q >/dev/null 2>&1; echo $?)"
igual "declara 6 secrets" "6" "$(printf '%s\n' "$STGN" | contar_secrets)"
igual "sus stacks, y solo esos" "certbot cloudflared nginx odoo postgres " \
  "$(servicios env.staging --profile cert -f envs/staging.yaml)"

# ports: !reset [] — el ingreso entra por el túnel, y el :80 de la LAN ya lo tiene producción.
igual "no publica ningún puerto" "" "$(printf '%s\n' "$STGN" | bloque nginx | binds)"

# Se siembra con datos reales de clientes. Son las dos mitades de la misma
# protección: un .env clonado de producción no alcanza para mandarles correo.
no_contiene "odoo sin la credencial SMTP"                        "zeptomail_smtp_password" "$(printf '%s\n' "$STGN" | bloque odoo)"
contiene    "un odoo.conf clonado no alcanza para mandar correo" 'ODOO_DISABLE_SMTP: "1"'  "$(printf '%s\n' "$STGN" | bloque odoo)"

# dnsmasq no se incluye, y no alcanzaba con no activarle el perfil: corre sobre el
# 53 con el stack de red del host y un .env copiado de producción lo levantaría.
no_contiene "dnsmasq no está ni con el perfil activo" "dnsmasq" \
  "$(COMPOSE_PROFILES=lan servicios env.staging -f envs/staging.yaml)"

# =====================================================================
titulo "prueba restaura, pero NO respalda"
# =====================================================================

# El trío que sostiene la garantía, y es estructural: timers.sh deriva qué units
# corresponden de la composición SIN perfiles. Con backup ahí, un timers-install en
# prueba dejaría una corrida nocturna escribiendo en el repositorio de producción.

no_contiene "backup fuera de la composición por defecto" "backup" \
  "$(servicios env.staging -f envs/staging.yaml)"

no_contiene "y fuera de la que consulta timers.sh" "backup" \
  "$(servicios env.staging --profile cert -f envs/staging.yaml)"

contiene "pero alcanzable para restaurar" "backup" \
  "$(servicios env.staging --profile restore -f envs/staging.yaml)"

# El contraste: en producción sí está por defecto, y por eso sus timers se instalan.
contiene "en producción sí está por defecto" "backup" \
  "$(servicios env.production -f envs/production.yaml)"

# =====================================================================
titulo "dnsmasq entra solo si el cliente tiene LAN"
# =====================================================================

# La única variación por cliente del diseño, y vive en el .env — no en un
# entrypoint aparte. Sin la clave, un deploy en VPS no levanta un DNS que no usa.
igual "sin COMPOSE_PROFILES no está" "alloy backup cloudflared grafana loki nginx odoo postgres prometheus " \
  "$(servicios env.production -f envs/production.yaml)"

igual "con COMPOSE_PROFILES=lan sí está" "alloy backup cloudflared dnsmasq grafana loki nginx odoo postgres prometheus " \
  "$(COMPOSE_PROFILES=lan servicios env.production -f envs/production.yaml)"

# =====================================================================
titulo "reglas que cruzan los tres"
# =====================================================================

# El bind tiene que fallar cerrado: sin LOCAL_IP el ports: publicaba en 0.0.0.0,
# que es exactamente lo que los principios prohíben.
SIN_IP=$(mktemp)
grep -v '^LOCAL_IP=' tests/fixtures/env.production > "$SIN_IP"
SIN_LOCAL_IP=$(docker compose --env-file "$SIN_IP" -f envs/production.yaml config 2>/dev/null | bloque nginx | binds)
rm -f "$SIN_IP"
igual "sin LOCAL_IP el bind cae a loopback, no a 0.0.0.0" "127.0.0.1 127.0.0.1 " "$SIN_LOCAL_IP"

# La identidad sale de .env en los tres, con un solo mecanismo que aprender: ni los
# entrypoints ni los compose de stack declaran name:.
igual "ningún compose declara name:" "0" \
  "$(grep -rl '^name:' envs/ stacks/ 2>/dev/null | wc -l | tr -d ' ')"

# El que atrapa un bind abierto es el conteo: un ports: sin IP no emite host_ip,
# así que la ausencia de '0.0.0.0' sola no prueba nada — solo cubre el literal.
# host_ip aparece únicamente dentro de un ports:, y el 0.0.0.0:2000 de las
# métricas de cloudflared —que no publica nada— queda afuera.

for caso in "producción:$PRODN" "prueba:$STGN" "development:$DEVN"; do
  nombre="${caso%%:*}"; cfg="${caso#*:}"
  no_contiene "$nombre no publica en 0.0.0.0" "host_ip: 0.0.0.0" "$cfg"
  igual "$nombre nombra una IP en cada puerto publicado" \
    "$(printf '%s\n' "$cfg" | grep -c 'published:')" \
    "$(printf '%s\n' "$cfg" | grep -c 'host_ip:')"
done

# =====================================================================
titulo "las tres plantillas de .env"
# =====================================================================

# Una plantilla por entorno es una copia por entorno: lo que puede pasar es que una
# clave nueva entre en un compose de capa compartido y solo se sume a una. Compose
# avisa por cada variable sin default que no esté declarada, así que ese warning
# —vacío en las tres— es la prueba de que ninguna plantilla se quedó atrás.

for caso in "producción:production:envs/production.yaml" "prueba:staging:envs/staging.yaml" "development:development:envs/development.yaml"; do
  nombre="${caso%%:*}"; resto="${caso#*:}"; plantilla="${resto%%:*}"; entrypoint="${resto#*:}"
  igual "$nombre no deja variables sin declarar en su plantilla" "" \
    "$(docker compose --env-file ".env.$plantilla.example" -f "$entrypoint" config -q 2>&1 | grep -i 'is not set' | tr '\n' ' ')"
  # El -f de arriba nunca ejerce el COMPOSE_FILE de la plantilla: sin esto, mover un
  # compose y olvidar la plantilla pasa el test y falla en el servidor.
  igual "$nombre apunta a su entrypoint desde la plantilla" "$entrypoint" \
    "$(sed -n 's/^COMPOSE_FILE=//p' ".env.$plantilla.example")"
done

resumen
