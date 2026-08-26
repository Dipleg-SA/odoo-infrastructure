#!/usr/bin/env bash
# Contrato de los tres entrypoints: qué capas, qué secrets y qué publica cada uno.
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

PROD=$(resuelto env.production --profile cert --profile restore -f docker/compose.yaml)
STG=$(resuelto  env.staging    --profile cert --profile restore -f docker/compose.staging.yaml)
DEV=$(resuelto  env.dev        -f docker/compose.dev.yaml)

# =====================================================================
titulo "producción — docker/compose.yaml"
# =====================================================================

igual "resuelve sin error" "0" "$(docker compose --env-file tests/fixtures/env.production -f docker/compose.yaml config -q >/dev/null 2>&1; echo $?)"
igual "declara 11 secrets" "11" "$(printf '%s\n' "$PROD" | contar_secrets)"
igual "levanta 11 servicios sin perfiles" \
  "alloy backup cloudflared dnsmasq grafana loki nginx odoo pgbouncer postgres prometheus " \
  "$(servicios env.production -f docker/compose.yaml)"
contiene "suma certbot y restore con sus perfiles" "certbot restore-db restore-files" \
  "$(servicios env.production --profile cert --profile restore -f docker/compose.yaml | tr ' ' '\n' | grep -E 'certbot|restore' | tr '\n' ' ' | sed 's/ $//')"

# La LAN entra sin pasar por el túnel: nivel 3 del criterio de bind.
igual "nginx publica 80 y 443 en LOCAL_IP" "10.0.0.2 10.0.0.2 " "$(printf '%s\n' "$PROD" | bloque nginx | binds)"

# El único stack que archiva WAL, porque es el único que respalda. Producción no
# lo fuerza por compose —vive en postgresql.conf, real por checkout— así que acá
# solo se confirma que su .example trae "on" por default, no en la config resuelta.
contiene "postgresql.conf.example archiva por default" "archive_mode    = on" \
  "$(cat docker/db/postgres/postgresql.conf.example)"

# Producción sí manda correo: es el contraste de los otros dos. smtp_server ya
# no está en la config resuelta —es literal de odoo.conf, real por checkout—
# así que acá solo se confirma que su .example trae el placeholder a reemplazar.
contiene "odoo lleva la credencial SMTP" "zeptomail_smtp_password" "$(printf '%s\n' "$PROD" | bloque odoo)"
contiene "odoo.conf.example trae el placeholder de smtp_server" "smtp_server = TU_SMTP_HOST" \
  "$(cat docker/app/odoo/odoo.conf.example)"

# El nombre de imagen es global al daemon: sin el tag por proyecto, el build de un
# stack pisa la imagen que corre el otro.
contiene "imágenes tagueadas por proyecto" "local/odoo:test-production" "$PROD"

# =====================================================================
titulo "staging — docker/compose.staging.yaml"
# =====================================================================

igual "resuelve sin error" "0" "$(docker compose --env-file tests/fixtures/env.staging -f docker/compose.staging.yaml config -q >/dev/null 2>&1; echo $?)"
igual "declara 8 secrets" "8" "$(printf '%s\n' "$STG" | contar_secrets)"
igual "sus capas, y solo esas" \
  "certbot cloudflared nginx odoo pgbouncer postgres restore-db restore-files " \
  "$(servicios env.staging --profile cert --profile restore -f docker/compose.staging.yaml)"

# ports: !reset [] — el ingreso entra por el túnel, y el :80 de la LAN ya lo tiene producción.
igual "no publica ningún puerto" "" "$(printf '%s\n' "$STG" | bloque nginx | binds)"

# Apunta a la stanza de producción para restaurar: archivando, la contaminaría.
contiene "postgres NO archiva WAL" "archive_mode=off" "$(printf '%s\n' "$STG" | bloque postgres)"

# Se siembra con datos reales de clientes. Son las dos mitades de la misma
# protección, y el fixture trae SMTP cargado a propósito: prueba el escenario que
# importa, que es un .env copiado de producción.

no_contiene "odoo sin la credencial SMTP"                        "zeptomail_smtp_password" "$(printf '%s\n' "$STG" | bloque odoo)"
contiene    "un odoo.conf clonado no alcanza para mandar correo" 'ODOO_DISABLE_SMTP: "1"'  "$(printf '%s\n' "$STG" | bloque odoo)"

# Si restore-db no usa la misma imagen que postgres, restaura con un binario
# distinto al que escribió el pgdata.
contiene "restore-db comparte imagen con postgres" "local/postgres:test-staging" \
  "$(printf '%s\n' "$STG" | bloque restore-db)"

# =====================================================================
titulo "development — docker/compose.dev.yaml"
# =====================================================================

igual "resuelve sin error" "0" "$(docker compose --env-file tests/fixtures/env.dev -f docker/compose.dev.yaml config -q >/dev/null 2>&1; echo $?)"
igual "declara 3 secrets" "3" "$(printf '%s\n' "$DEV" | contar_secrets)"
igual "solo proxy, datos y aplicación" "nginx odoo pgbouncer postgres " "$(servicios env.dev -f docker/compose.dev.yaml)"

# server-plain no escucha en el 443: publicarlo ataría un puerto para nada.
igual "publica solo el 80, en loopback" "127.0.0.1 " "$(printf '%s\n' "$DEV" | bloque nginx | binds)"

# Fijada en el entrypoint y no por NGINX_MODE: un .env sin la clave montaría
# server-tls y nginx no arranca, porque no hay certificado.
contiene    "monta el config sin TLS" "server-plain.conf" "$(printf '%s\n' "$DEV" | bloque nginx)"
no_contiene "y ninguna con TLS"          "server-tls"                 "$DEV"

# No archiva ni restaura, así que no lleva la credencial de R2.
no_contiene "postgres sin credencial de R2" "pgbackrest_r2_credentials" "$(printf '%s\n' "$DEV" | bloque postgres)"
contiene    "un odoo.conf clonado no alcanza para mandar correo" 'ODOO_DISABLE_SMTP: "1"' "$(printf '%s\n' "$DEV" | bloque odoo)"

# =====================================================================
titulo "reglas que cruzan los tres"
# =====================================================================

# El bind tiene que fallar cerrado: sin LOCAL_IP el ports: publicaba en 0.0.0.0,
# que es exactamente lo que los principios prohíben.
SIN_IP=$(mktemp)
grep -v '^LOCAL_IP=' tests/fixtures/env.production > "$SIN_IP"
SIN_LOCAL_IP=$(docker compose --env-file "$SIN_IP" -f docker/compose.yaml config 2>/dev/null | bloque nginx | binds)
rm -f "$SIN_IP"
igual "sin LOCAL_IP el bind cae a loopback, no a 0.0.0.0" "127.0.0.1 127.0.0.1 " "$SIN_LOCAL_IP"

# La identidad sale de .env en los tres, con un solo mecanismo que aprender.
# docker/compose.yaml va nombrado aparte: el glob no lo matchea, y es el único de
# los tres cuyo nombre de proyecto tagea las imágenes de producción.

igual "ningún compose declara name:" "0" "$(grep -c '^name:' docker/compose.yaml docker/compose.*.yaml | grep -v ':0$' | wc -l | tr -d ' ')"

# El que atrapa un bind abierto es el conteo: un ports: sin IP no emite host_ip,
# así que la ausencia de '0.0.0.0' sola no prueba nada — solo cubre el literal.
# host_ip aparece únicamente dentro de un ports:, y el 0.0.0.0:2000 de las
# métricas de cloudflared —que no publica nada— queda afuera.

for caso in "producción:$PROD" "staging:$STG" "development:$DEV"; do
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

for caso in "producción:prod:docker/compose.yaml" "staging:stag:docker/compose.staging.yaml" "development:dev:docker/compose.dev.yaml"; do
  nombre="${caso%%:*}"; resto="${caso#*:}"; plantilla="${resto%%:*}"; entrypoint="${resto#*:}"
  igual "$nombre no deja variables sin declarar en su plantilla" "" \
    "$(docker compose --env-file ".env.$plantilla.example" -f "$entrypoint" config -q 2>&1 | grep -i 'is not set' | tr '\n' ' ')"
  # El -f de arriba nunca ejerce el COMPOSE_FILE de la plantilla: sin esto, mover un
  # compose y olvidar la plantilla pasa el test y falla en el servidor.
  igual "$nombre apunta a su entrypoint desde la plantilla" "$entrypoint" \
    "$(sed -n 's/^COMPOSE_FILE=//p' ".env.$plantilla.example")"
done

resumen
