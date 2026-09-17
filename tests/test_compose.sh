#!/usr/bin/env bash
# Contrato de los tres runtimes
# Resuelve las composiciones reales y comprueba aislamiento, perfiles y puertos.

cd "$(dirname "$0")/.."
. tests/lib.sh
set -o pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Acceso a la composición
# Cada consulta usa la plantilla privada del runtime que corresponde.
resuelto() {
  local entorno="$1"; shift
  docker compose --env-file "runtime/$entorno/compose.env.example" \
    -f "runtime/$entorno/compose.yaml" "$@" config 2>/dev/null
}

servicios() {
  local entorno="$1"; shift
  docker compose --env-file "runtime/$entorno/compose.env.example" \
    -f "runtime/$entorno/compose.yaml" "$@" config --services 2>/dev/null | sort | tr '\n' ' '
}

# Extractores
# Aíslan servicios, puertos y nombres de recursos de la salida normalizada.
contar_secrets() { sed -n '/^secrets:/,$p' | grep -cE '^  [a-z0-9_]+:$'; }
bloque()         {
  awk -v servicio="$1" '
    $0 == "  " servicio ":" { dentro=1 }
    dentro { print }
    dentro && $0 ~ /^  [a-z0-9_-]+:$/ && $0 != "  " servicio ":" { exit }
  '
}
binds()          { grep -B1 -E '^[[:space:]]+target: (80|443)$' | sed -n 's/^[[:space:]]*host_ip: //p' | tr '\n' ' '; }
recursos() {
  awk '
    /^networks:/ { seccion = 1; next }
    /^volumes:/ { seccion = 2; next }
    /^secrets:/ { seccion = 0; next }
    seccion && /^    name:/ { sub(/^    name: /, ""); gsub(/"/, ""); print }
  '
}

# Contextos temporales de edición
# Ejercen contexto.sh sin usar archivos privados ni un daemon Docker.
contexto_prueba() {
  local nombre="$1" valores="$2" root
  root="$TMP/contexto-$nombre"
  mkdir -p "$root/scripts/lib" "$root/runtime/desarrollo"
  cp scripts/lib/contexto.sh "$root/scripts/lib/contexto.sh"
  printf 'services: {}\n' > "$root/runtime/desarrollo/compose.yaml"
  printf 'COMPOSE_PROJECT_NAME=prueba-%s\n%s\n' "$nombre" "$valores" \
    > "$root/runtime/desarrollo/compose.env"
  printf '%s\n' "$root"
}

# Validación de edición
# Comprueba las dos combinaciones válidas y todos los rechazos del contrato.
validar_contexto() {
  (cd "$1" && ENTORNO=desarrollo bash scripts/lib/contexto.sh validar)
}

ROOT_COMMUNITY=$(contexto_prueba community $'ODOO_EDITION=community\nTAG=19.0-ce-2026-09-16')
ROOT_ENTERPRISE=$(contexto_prueba enterprise $'ODOO_EDITION=enterprise\nTAG=19.0-ee-2026-09-16')
ROOT_SIN_EDICION=$(contexto_prueba sin-edicion $'TAG=19.0-ce-2026-09-16')
ROOT_EDICION_INVALIDA=$(contexto_prueba edicion-invalida $'ODOO_EDITION=standard\nTAG=19.0-ce-2026-09-16')
ROOT_SIN_TAG=$(contexto_prueba sin-tag $'ODOO_EDITION=community')
ROOT_TAG_INVALIDO=$(contexto_prueba tag-invalido $'ODOO_EDITION=community\nTAG=19.0-ce-hoy')
ROOT_PREFIJO_INCOMPATIBLE=$(contexto_prueba prefijo-incompatible $'ODOO_EDITION=enterprise\nTAG=19.0-ce-2026-09-16')

sale_con "contexto acepta Community" 0 validar_contexto "$ROOT_COMMUNITY"
sale_con "contexto acepta Enterprise" 0 validar_contexto "$ROOT_ENTERPRISE"
sale_con "contexto rechaza edición ausente" 2 validar_contexto "$ROOT_SIN_EDICION"
sale_con "contexto rechaza edición inválida" 2 validar_contexto "$ROOT_EDICION_INVALIDA"
sale_con "contexto rechaza TAG ausente" 2 validar_contexto "$ROOT_SIN_TAG"
sale_con "contexto rechaza TAG inválido" 2 validar_contexto "$ROOT_TAG_INVALIDO"
sale_con "contexto rechaza prefijo incompatible" 2 validar_contexto "$ROOT_PREFIJO_INCOMPATIBLE"

# Contrato en plantillas
# Las tres plantillas exponen la selección plana que consumen los operadores.
for entorno in desarrollo staging produccion; do
  contiene "$entorno declara edición Community" "ODOO_EDITION=community" \
    "$(grep -E '^(ODOO_EDITION|TAG)=' "runtime/$entorno/compose.env.example")"
  contiene "$entorno declara TAG Community" "TAG=19.0-ce-2026-09-16" \
    "$(grep -E '^(ODOO_EDITION|TAG)=' "runtime/$entorno/compose.env.example")"
done

# Development
# El entorno local incluye solo proxy, datos y aplicación.
for entorno in desarrollo staging produccion; do
  salida=$(resuelto "$entorno"); codigo=$?
  igual "$entorno config devuelve exit 0" "0" "$codigo"
  contiene "$entorno config devuelve una estructura" "services:" "$salida"
  lista=$(servicios "$entorno"); codigo=$?
  igual "$entorno consulta servicios con exit 0" "0" "$codigo"
  contiene "$entorno devuelve al menos un servicio" " " "$lista"
done

DEV=$(resuelto desarrollo)
igual "desarrollo resuelve sin error" "0" "$(docker compose --env-file runtime/desarrollo/compose.env.example -f runtime/desarrollo/compose.yaml config -q >/dev/null 2>&1; echo $?)"
igual "desarrollo declara 2 secretos" "2" "$(printf '%s\n' "$DEV" | contar_secrets)"
igual "desarrollo solo incluye nginx, odoo y postgres" "nginx odoo postgres " "$(servicios desarrollo)"
no_contiene "desarrollo no incluye el receptor" "addons-webhook" "$(servicios desarrollo)"
igual "desarrollo publica solo el 80 en loopback" "127.0.0.1 " "$(printf '%s\n' "$DEV" | bloque nginx | binds)"
igual "desarrollo usa su puerto aislado" "8081 " \
  "$(printf '%s\n' "$DEV" | bloque nginx | sed -n 's/^ *published: "//p' | tr -d '"' | tr '\n' ' ')"
contiene "desarrollo monta su config sin TLS" "/runtime/desarrollo/config/nginx/server-plain.conf" "$(printf '%s\n' "$DEV" | bloque nginx)"
no_contiene "desarrollo no monta config TLS" "server-tls.conf" "$DEV"
no_contiene "desarrollo no incluye pgbouncer" "pgbouncer" "$DEV"
contiene "la imagen postgres usa la identidad del runtime" "local/postgres:odoo-desarrollo" "$(printf '%s\n' "$DEV" | bloque postgres)"
contiene "la imagen nginx usa la identidad del runtime" "local/nginx:odoo-desarrollo" "$(printf '%s\n' "$DEV" | bloque nginx)"
contiene "desarrollo desactiva SMTP de Odoo" 'ODOO_DISABLE_SMTP: "1"' "$(printf '%s\n' "$DEV" | bloque odoo)"
contiene "desarrollo usa una imagen Odoo explícita" "local/odoo:19.0-desarrollo-bootstrap" "$(printf '%s\n' "$DEV" | bloque odoo)"
no_contiene "desarrollo no monta addons del host" "/mnt/extra-addons" "$(printf '%s\n' "$DEV" | bloque odoo)"

# Production
# Certbot se activa de forma explícita y el proxy conserva el bind de la LAN.
PROD=$(LOCAL_IP=192.0.2.10 COMPOSE_PROFILES=cert resuelto produccion)
igual "producción resuelve sin error" "0" "$(LOCAL_IP=192.0.2.10 COMPOSE_PROFILES=cert docker compose --env-file runtime/produccion/compose.env.example -f runtime/produccion/compose.yaml config -q >/dev/null 2>&1; echo $?)"
igual "producción declara 9 secretos" "9" "$(printf '%s\n' "$PROD" | contar_secrets)"
igual "producción incluye sus once servicios" "addons-webhook alloy backup certbot cloudflared grafana loki nginx odoo postgres prometheus " \
  "$(COMPOSE_PROFILES=cert servicios produccion)"
contiene "producción usa una imagen Odoo explícita" "local/odoo:19.0-produccion-bootstrap" "$(printf '%s\n' "$PROD" | bloque odoo)"
no_contiene "producción no monta addons del host" "/mnt/extra-addons" "$(printf '%s\n' "$PROD" | bloque odoo)"
contiene "producción monta la ruta versionada del receptor" \
  "/stacks/nginx/config/addons-webhook.locations" "$(printf '%s\n' "$PROD" | bloque nginx)"
contiene "la ruta pública apunta solo al endpoint GitHub" \
  'proxy_pass http://$addons_webhook:8080/github' "$(cat stacks/nginx/config/addons-webhook.locations)"
contiene "la ruta pública usa el path exacto" \
  "location = /webhooks/addons" "$(cat stacks/nginx/config/addons-webhook.locations)"
contiene "la ruta pública limita el método a POST" \
  'if ($request_method != POST) { return 405; }' "$(cat stacks/nginx/config/addons-webhook.locations)"
contiene "producción monta config TLS" "/runtime/produccion/config/nginx/server-tls.conf" "$(printf '%s\n' "$PROD" | bloque nginx)"
igual "producción publica en la IP declarada" "192.0.2.10 192.0.2.10 " "$(printf '%s\n' "$PROD" | bloque nginx | binds)"
contiene "certbot comparte el volumen del certificado" "letsencrypt" "$(printf '%s\n' "$PROD" | bloque certbot)"
contiene "postgres escribe el dump compartido" "dumps" "$(printf '%s\n' "$PROD" | bloque postgres)"
contiene "backup lee el dump junto al filestore" "dumps" "$(printf '%s\n' "$PROD" | bloque backup)"
contiene "backup conserva el filestore para restaurar" "odoo-data" "$(printf '%s\n' "$PROD" | bloque backup)"
igual "Grafana publica solo en loopback" "127.0.0.1 " \
  "$(printf '%s\n' "$PROD" | bloque grafana | grep -B1 'target: 3000' | sed -n 's/^ *host_ip: //p' | tr '\n' ' ')"
for servicio in prometheus loki alloy; do
  igual "$servicio no publica puertos" "" "$(printf '%s\n' "$PROD" | bloque "$servicio" | sed -n 's/^ *published: //p' | tr '\n' ' ')"
done

# Staging
# La prueba comparte la red edge, pero no publica servicios en la LAN ni respalda.
STAGE=$(COMPOSE_PROFILES=cert,restore resuelto staging)
igual "staging resuelve sin error" "0" "$(COMPOSE_PROFILES=cert,restore docker compose --env-file runtime/staging/compose.env.example -f runtime/staging/compose.yaml config -q >/dev/null 2>&1; echo $?)"
igual "staging declara 7 secretos" "7" "$(printf '%s\n' "$STAGE" | contar_secrets)"
igual "staging incluye solo sus cinco servicios por defecto" "cloudflared nginx odoo postgres " "$(servicios staging)"
no_contiene "staging no incluye el receptor" "addons-webhook" "$(servicios staging)"
contiene "staging monta la plantilla vacía del receptor" \
  "/runtime/staging/config/nginx/addons-webhook.locations" "$(printf '%s\n' "$STAGE" | bloque nginx)"
igual "staging publica en loopback" "127.0.0.1 127.0.0.1 " "$(printf '%s\n' "$STAGE" | bloque nginx | binds)"
igual "staging usa los puertos reservados" "8080 8443 " \
  "$(printf '%s\n' "$STAGE" | bloque nginx | sed -n 's/^ *published: "//p' | tr -d '"' | tr '\n' ' ')"
contiene "staging conserva el secret de alertas" "zeptomail_smtp_password" "$(printf '%s\n' "$STAGE" | bloque odoo)"
contiene "staging desactiva SMTP de Odoo" 'ODOO_DISABLE_SMTP: "1"' "$(printf '%s\n' "$STAGE" | bloque odoo)"
contiene "staging usa una imagen Odoo explícita" "local/odoo:19.0-staging-bootstrap" "$(printf '%s\n' "$STAGE" | bloque odoo)"
no_contiene "staging no monta addons del host" "/mnt/extra-addons" "$(printf '%s\n' "$STAGE" | bloque odoo)"
no_contiene "staging no incluye dnsmasq aunque pida LAN" "dnsmasq" "$(COMPOSE_PROFILES=lan servicios staging)"
no_contiene "backup no se activa por defecto en staging" "backup" "$(servicios staging)"
no_contiene "backup queda fuera del perfil de certificado" "backup" "$(COMPOSE_PROFILES=cert servicios staging)"
contiene "backup queda disponible con restore" "backup" "$(COMPOSE_PROFILES=restore servicios staging)"
contiene "backup está activo por defecto en producción" "backup" "$(servicios produccion)"

# DNS y aislamiento
# Solo producción declara dnsmasq, y cada runtime recibe recursos con nombre propio.
no_contiene "producción no activa dnsmasq por defecto" "dnsmasq" "$(servicios produccion)"
contiene "producción activa dnsmasq con el perfil LAN" "dnsmasq" "$(COMPOSE_PROFILES=lan servicios produccion)"

# Los perfiles declarados siguen siendo visibles aunque estén inactivos.
contiene "producción declara cert" "cert" \
  "$(docker compose --env-file runtime/produccion/compose.env.example -f runtime/produccion/compose.yaml config --profiles)"
contiene "producción declara lan" "lan" \
  "$(docker compose --env-file runtime/produccion/compose.env.example -f runtime/produccion/compose.yaml config --profiles)"
contiene "staging declara restore" "restore" \
  "$(docker compose --env-file runtime/staging/compose.env.example -f runtime/staging/compose.yaml config --profiles)"
no_contiene "staging no declara lan" "lan" \
  "$(docker compose --env-file runtime/staging/compose.env.example -f runtime/staging/compose.yaml config --profiles)"

for entorno in desarrollo staging produccion; do
  cfg=$(resuelto "$entorno")
  printf '%s\n' "$cfg" | recursos | sort -u > "$TMP/$entorno.recursos"
  esperado="odoo-$entorno"
  contiene "$entorno tiene identidad Compose propia" "name: $esperado" "$cfg"
  no_contiene "$entorno no tiene recursos sin prefijo" "name: edge" "$(printf '%s\n' "$cfg" | sed -n '/^networks:/,/^volumes:/p')"
  igual "$entorno prefija cada red y volumen" "" "$(grep -v "^${esperado}_" "$TMP/$entorno.recursos" || true)"
done
igual "desarrollo no comparte recursos con staging" "" "$(comm -12 "$TMP/desarrollo.recursos" "$TMP/staging.recursos")"
igual "desarrollo no comparte recursos con producción" "" "$(comm -12 "$TMP/desarrollo.recursos" "$TMP/produccion.recursos")"
igual "staging no comparte recursos con producción" "" "$(comm -12 "$TMP/staging.recursos" "$TMP/produccion.recursos")"

# Selector legacy
# Un COMPOSE_FILE raíz no puede cambiar la composición explícita elegida por ENTORNO.
SELECTOR_ROOT="$TMP/checkout"
mkdir -p "$SELECTOR_ROOT/runtime/desarrollo" "$SELECTOR_ROOT/scripts/lib"
cp runtime/desarrollo/compose.yaml runtime/desarrollo/compose.env.example "$SELECTOR_ROOT/runtime/desarrollo/"
mv "$SELECTOR_ROOT/runtime/desarrollo/compose.env.example" "$SELECTOR_ROOT/runtime/desarrollo/compose.env"
ln -s "$PWD/stacks" "$SELECTOR_ROOT/stacks"
cp scripts/lib/contexto.sh "$SELECTOR_ROOT/scripts/lib/contexto.sh"
printf 'COMPOSE_FILE=runtime/produccion/compose.yaml\nCOMPOSE_PROJECT_NAME=legacy-root\n' > "$TMP/.env"
LEGACY_SERVICIOS=$(cd "$TMP" && COMPOSE_FILE=runtime/produccion/compose.yaml ENTORNO=desarrollo \
  "$SELECTOR_ROOT/scripts/lib/contexto.sh" compose config --services 2>/dev/null | sort | tr '\n' ' ')
igual "el selector COMPOSE_FILE raíz no cambia desarrollo" "nginx odoo postgres " "$LEGACY_SERVICIOS"

# Ejemplos y archivos retirados
# Las tres plantillas resuelven sin variables faltantes ni selectores de raíz.
for entorno in desarrollo staging produccion; do
  salida=$(docker compose --env-file "runtime/$entorno/compose.env.example" \
    -f "runtime/$entorno/compose.yaml" config -q 2>&1)
  no_contiene "$entorno no deja variables sin declarar" "is not set" "$salida"
  no_contiene "$entorno no deja variables vacías requeridas" "is missing a value" "$salida"
done
for archivo in .env.development.example .env.staging.example .env.production.example \
               envs/development.yaml envs/staging.yaml envs/production.yaml; do
  igual "$archivo fue retirado" "0" "$([ ! -e "$archivo" ]; echo $?)"
done

resumen
