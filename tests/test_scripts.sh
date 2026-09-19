#!/usr/bin/env bash
# cert.sh y los dos de secrets, contra un checkout falso y un stub de docker.
# Cada caso corre el script de verdad, no una reimplementación: se copia a un árbol
# temporal porque los tres hacen cd al padre de su propio directorio.

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
STUB_DIR="$TMP/stub"; mkdir -p "$STUB_DIR"; export STUB_DIR
trap 'rm -rf "$TMP"' EXIT
PATH="$REPO_ROOT/tests/stubs:$PATH"
export ENTORNO=desarrollo

# nuke debe limpiar solo el runtime seleccionado: los clones bare y el control
# son compartidos, y los candidatos/builds de los otros entornos no se pueden borrar.
NUKE=$(make -n ENTORNO=desarrollo nuke 2>&1); NUKE_CODIGO=$?
igual "make -n nuke termina correctamente" "0" "$NUKE_CODIGO"
contiene "nuke limita addons al entorno seleccionado" 'runtime/${ENTORNO}/addons' "$NUKE"
contiene "nuke limita builds al entorno seleccionado" 'runtime/addons/builds/${ENTORNO}' "$NUKE"
no_contiene "nuke conserva los clones bare compartidos" "runtime/addons/.repos" "$NUKE"
no_contiene "nuke conserva el estado del control plane" "runtime/control/state" "$NUKE"

# Checkout falso
# Cada entorno tiene su composición y variables privadas bajo runtime/.

crear_root() {
  local nombre="$1" root entorno; shift
  root="$TMP/$nombre"
  mkdir -p "$root/scripts/lib"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$REPO_ROOT/scripts/lib/compose.sh" \
    "$REPO_ROOT/scripts/lib/contexto.sh" "$root/scripts/lib/"
  for s in "$@"; do cp "$REPO_ROOT/scripts/$s" "$root/scripts/"; done
  cp "$REPO_ROOT/Makefile" "$root/"
  cp -R "$REPO_ROOT/.make" "$root/"
  for entorno in desarrollo staging produccion; do
    mkdir -p "$root/runtime/$entorno"
    printf 'services: {}\n' > "$root/runtime/$entorno/compose.yaml"
    printf 'COMPOSE_PROJECT_NAME=%s-%s\nPUBLIC_HOSTNAME=odoo.example.test\nODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' \
      "$nombre" "$entorno" > "$root/runtime/$entorno/compose.env"
  done
  printf '%s' "$root"
}

llamadas() { cat "$STUB_DIR/llamadas" 2>/dev/null; }
reset_stub() {
  : > "$STUB_DIR/llamadas"
  : > "$STUB_DIR/config"
  : > "$STUB_DIR/salida"
  : > "$STUB_DIR/systemctl"
  rm -f "$STUB_DIR/ps-q"
}

# Fixtures ausentes deben fallar en vez de convertir una llamada no preparada en un falso verde.
# El contrato se prueba en un directorio separado para no alterar las respuestas de los casos.
titulo "stubs — una respuesta no preparada falla"
STUB_FALTANTE="$TMP/stub-faltante"; mkdir -p "$STUB_FALTANTE"
sale_con "docker exige su fixture" 99 env STUB_DIR="$STUB_FALTANTE" \
  "$REPO_ROOT/tests/stubs/docker" compose config --services
sale_con "systemctl exige su fixture" 99 env STUB_DIR="$STUB_FALTANTE" \
  "$REPO_ROOT/tests/stubs/systemctl" is-enabled docker

# =====================================================================
titulo "cert.sh — lo que le llega de verdad a certbot"
# =====================================================================

ROOT=$(crear_root cert)
igual "el checkout falso no crea selector .env raíz" "0" "$([ ! -e "$ROOT/.env" ]; echo $?)"
mkdir -p "$ROOT/stacks/certbot/scripts"
cp "$REPO_ROOT/stacks/certbot/scripts/cert.sh" "$ROOT/stacks/certbot/scripts/"
reset_stub
printf '  Expiry Date: 2026-11-01 12:00:00+00:00 (VALID: 80 days)\n' > "$STUB_DIR/salida"
printf 'idcontenedor\n' > "$STUB_DIR/ps-q"

(cd "$ROOT" && ./stacks/certbot/scripts/cert.sh renew --force-renewal >/dev/null 2>&1)

# El bug que se shippeó: cmd_renew no reenviaba "$@" y el flag se perdía en silencio.
contiene "renew reenvía --force-renewal a certbot" \
  "run --rm -T certbot renew --non-interactive --force-renewal" "$(llamadas)"

# Un certificado renovado que nginx no releyó sigue sirviendo el viejo hasta que vence.
contiene "y recarga nginx después" "exec -T nginx nginx -s reload" "$(llamadas)"

# --- La métrica ---
# Única fuente de la alerta de vencimiento desde que Traefik salió del repo.

METRICA=$(cat "$ROOT/runtime/desarrollo/state/textfile/cert.prom" 2>/dev/null)
contiene "declara TYPE gauge"          "# TYPE odoo_cert_expiry_timestamp_seconds gauge" "$METRICA"
contiene "etiqueta con el hostname"    'host="odoo.example.test"'                        "$METRICA"

# El epoch de 2026-11-01 12:00:00 UTC. Es el chequeo portable: en GNU parsea el
# primer date y en BSD el segundo, y la métrica tiene que dar igual en los dos.
contiene "con el vencimiento en epoch UTC" "1793534400" "$METRICA"

# --- nginx abajo ---
# Best-effort: si no hay nada que recargar, no es un fallo de la renovación.

reset_stub
printf '  Expiry Date: 2026-11-01 12:00:00+00:00 (VALID: 80 days)\n' > "$STUB_DIR/salida"
: > "$STUB_DIR/ps-q"
SALIDA=$( (cd "$ROOT" && ./stacks/certbot/scripts/cert.sh renew 2>&1) )
igual    "con nginx abajo igual sale con 0" "0" "$( (cd "$ROOT" && ./stacks/certbot/scripts/cert.sh renew >/dev/null 2>&1); echo $?)"
contiene "y lo avisa"                        "no está corriendo" "$SALIDA"

# --- Uso ---
sale_con "un subcomando inventado sale con 2" 2 bash "$ROOT/stacks/certbot/scripts/cert.sh" inventado

# =====================================================================
titulo "secrets-init.sh — la lista sale de la composición"
# =====================================================================

ROOT=$(crear_root secrets secrets-init.sh secrets-perms.sh)
reset_stub

# Lo que declara un entrypoint de development: dos, y los dos generables.
cat > "$STUB_DIR/config" <<'EOF'
secrets:
  odoo_admin_password:
    file: /repo/secrets/odoo_admin_password
  postgres_password:
    file: /repo/secrets/postgres_password
EOF

SALIDA=$( (cd "$ROOT" && ./scripts/secrets-init.sh 2>&1) )
igual "crea exactamente los 2 declarados" "2" "$(ls "$ROOT/runtime/desarrollo/secrets" | wc -l | tr -d ' ')"
contiene "y dice cuáles omite"            "omitido (este runtime no lo declara): runtime/desarrollo/secrets/cloudflare_api_token" "$SALIDA"
contiene "sin dejar nada pendiente"       "Todos los secrets tienen valor" "$SALIDA"

# hex y no base64: los / + = rompen a cualquier consumidor que arme una URI.
igual "genera 64 hex" "0" \
  "$(grep -qE '^[0-9a-f]{64}$' "$ROOT/runtime/desarrollo/secrets/postgres_password"; echo $?)"

# --- Idempotencia ---
# Se corre de nuevo en cada checkout que suma una capa: pisar un valor cargado
# sería irrecuperable para los que no se generan.

ANTES=$(cat "$ROOT/runtime/desarrollo/secrets/postgres_password")
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-init.sh 2>&1) )
igual    "no pisa un valor ya cargado" "$ANTES" "$(cat "$ROOT/runtime/desarrollo/secrets/postgres_password")"
contiene "y lo dice"                   "skip (ya existe)" "$SALIDA"

# --- Sin composición ---
# Sin saber qué declara el stack, crear los once sería fabricar archivos inertes.

rm -f "$STUB_DIR/config"
: > "$STUB_DIR/config"
sale_con "sin composición legible aborta" 1 bash -c "cd '$ROOT' && ./scripts/secrets-init.sh"

# =====================================================================
titulo "secrets-init.sh — secretos del control plane"
# =====================================================================

ROOT_CONTROL=$(crear_root webhook secrets-init.sh)
reset_stub
cat > "$STUB_DIR/config" <<'EOF'
secrets:
  postgres_password:
    file: /repo/secrets/postgres_password
services:
  addons-webhook:
    volumes:
      - source: /repo/runtime/control/secrets/addons_webhook_secret
        target: /run/secrets/addons_webhook_secret
EOF
SALIDA=$( (cd "$ROOT_CONTROL" && ENTORNO=produccion ./scripts/secrets-init.sh 2>&1) )
igual "crea el secret operativo de producción" "1" \
  "$(find "$ROOT_CONTROL/runtime/produccion/secrets" -type f | wc -l | tr -d ' ')"
igual "crea los cuatro secretos del control plane" "4" \
  "$(find "$ROOT_CONTROL/runtime/control/secrets" -type f | wc -l | tr -d ' ')"
igual "genera la firma del webhook" "0" \
  "$(grep -qE '^[0-9a-f]{64}$' "$ROOT_CONTROL/runtime/control/secrets/addons_webhook_secret"; echo $?)"
contiene "informa los marcadores Git del control plane" \
  "runtime/control/secrets/git_readonly_key" "$SALIDA"

# =====================================================================
titulo "secrets-perms.sh --check"
# =====================================================================

# postgres_exporter_password lo lee alloy, que corre como root: es el único sin GID
# exigido, así que se puede probar el resto de la lógica sin ser root.

printf 'valor\n' > "$ROOT/runtime/desarrollo/secrets/postgres_exporter_password"
chmod 640 "$ROOT/runtime/desarrollo/secrets/postgres_exporter_password"
rm -f "$ROOT/runtime/desarrollo/secrets/postgres_password" "$ROOT/runtime/desarrollo/secrets/odoo_admin_password"

sale_con "un secret en 640 pasa" 0 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"

chmod 600 "$ROOT/runtime/desarrollo/secrets/postgres_exporter_password"
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-perms.sh --check 2>&1) )
sale_con "un 600 no pasa" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"
contiene "y nombra el modo que encontró" "permisos 600, esperado 640" "$SALIDA"

# El marcador es lo que separa "el archivo existe" de "el valor está cargado".
chmod 640 "$ROOT/runtime/desarrollo/secrets/postgres_exporter_password"
printf 'CAMBIAR' > "$ROOT/runtime/desarrollo/secrets/postgres_exporter_password"
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-perms.sh --check 2>&1) )
sale_con "un marcador sin reemplazar no pasa" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"
contiene "y lo nombra"                        "todavía tiene el marcador" "$SALIDA"

# --- El GID ---
# Sin root no se puede poner el grupo esperado, pero sí probar que lo exige: el
# archivo nace con el grupo del que corre el test, que nunca es el 65532 de cloudflared.

printf 'valor\n' > "$ROOT/runtime/desarrollo/secrets/postgres_exporter_password"
printf 'token\n' > "$ROOT/runtime/desarrollo/secrets/cloudflare_tunnel_token"
chmod 640 "$ROOT/runtime/desarrollo/secrets/cloudflare_tunnel_token"
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-perms.sh --check 2>&1) )
sale_con "un grupo que no es el del consumidor no pasa" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"
contiene "y nombra el GID esperado" "esperado 65532" "$SALIDA"

rm -rf "$ROOT/runtime/desarrollo/secrets"
sale_con "sin secrets/ aborta" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"

# =====================================================================
titulo "monitoring-role.sh — contexto y secreto del runtime"
# =====================================================================

ROOT_MON=$(crear_root monitoring)
mkdir -p "$ROOT_MON/stacks/alloy/scripts" "$ROOT_MON/runtime/produccion/secrets"
ROOT_MON="$(cd "$ROOT_MON" && pwd -P)"
cp "$REPO_ROOT/stacks/alloy/scripts/monitoring-role.sh" "$ROOT_MON/stacks/alloy/scripts/"
printf 'alloy\n' > "$STUB_DIR/servicios-sin-perfil"
printf 'password-de-prueba\n' > "$ROOT_MON/runtime/produccion/secrets/postgres_exporter_password"
chmod 640 "$ROOT_MON/runtime/produccion/secrets/postgres_exporter_password"
reset_stub
SALIDA=$( (cd "$ROOT_MON" && ENTORNO=produccion ./stacks/alloy/scripts/monitoring-role.sh 2>&1) )
contiene "monitoring-role usa el secreto del runtime" "monitoring-role listo" "$SALIDA"
contiene "monitoring-role usa la composición del entorno" \
  "-f $ROOT_MON/runtime/produccion/compose.yaml" "$(llamadas)"
rm -f "$STUB_DIR/servicios-sin-perfil"

# =====================================================================
titulo "config-init.sh — qué stack está activo decide qué bootstrapea"
# =====================================================================

ROOT=$(crear_root config config-init.sh)
reset_stub
mkdir -p "$ROOT/stacks/odoo/image"
printf 'FROM odoo:19.0\n' > "$ROOT/stacks/odoo/image/Dockerfile"

# Dos stacks activos, uno con dos .example (uno anidado) y otro sin config/ propia.
mkdir -p "$ROOT/stacks/nginx/config" "$ROOT/stacks/grafana/config/provisioning/alerting"
printf 'default;\n' > "$ROOT/stacks/nginx/config/00-http.conf.example"
printf 'de-mas;\n' > "$ROOT/stacks/nginx/config/odoo.locations.example"
printf 'TU_EMAIL_ALERTA_TO\n' > "$ROOT/stacks/grafana/config/provisioning/alerting/contact-points.yaml.example"
printf '%s\n' 'nginx' 'grafana' > "$STUB_DIR/servicios"

SALIDA=$( (cd "$ROOT" && ./scripts/config-init.sh 2>&1) )
igual "crea los 2 de nginx bajo el runtime" "0" \
  "$([ -f "$ROOT/runtime/desarrollo/config/nginx/00-http.conf" ] && [ -f "$ROOT/runtime/desarrollo/config/nginx/odoo.locations" ]; echo $?)"
igual "y el anidado de grafana bajo el runtime" "0" \
  "$([ -f "$ROOT/runtime/desarrollo/config/grafana/provisioning/alerting/contact-points.yaml" ]; echo $?)"
igual "no escribe configuraciones en los directorios versionados" "0" \
  "$([ ! -e "$ROOT/stacks/nginx/config/00-http.conf" ] && [ ! -e "$ROOT/addons" ]; echo $?)"
igual "guarda la línea de Odoo para el receptor" "19.0" "$(cat "$ROOT/runtime/control/state/odoo-version")"

# --- Idempotencia: no pisa lo cargado a mano ---

printf 'editado a mano\n' > "$ROOT/runtime/desarrollo/config/nginx/00-http.conf"
printf 'FROM odoo:18.0\n' > "$ROOT/stacks/odoo/image/Dockerfile"
SALIDA=$( (cd "$ROOT" && ./scripts/config-init.sh 2>&1) )
igual    "no pisa un archivo ya cargado" "editado a mano" "$(cat "$ROOT/runtime/desarrollo/config/nginx/00-http.conf")"
contiene "y lo dice"                     "skip (ya existe)" "$SALIDA"
igual "actualiza la línea derivada si cambia Odoo" "18.0" "$(cat "$ROOT/runtime/control/state/odoo-version")"

# Odoo activo
# La configuración privada permanece en runtime, y addons los gestiona su propio flujo.

printf '%s\n' 'nginx' 'grafana' 'odoo' > "$STUB_DIR/servicios"
SALIDA=$( (cd "$ROOT" && ./scripts/config-init.sh 2>&1) )
igual "no crea configuración fuera del runtime" "0" \
  "$([ ! -e "$ROOT/addons" ] && [ -d "$ROOT/runtime/desarrollo/config" ]; echo $?)"

# --- Un stack ausente no deja rastro ---
# dnsmasq no está entre los activos: su .example no se toca.

mkdir -p "$ROOT/stacks/dnsmasq/config"
printf 'TU_IP_LOCAL\n' > "$ROOT/stacks/dnsmasq/config/dnsmasq.conf.example"
( cd "$ROOT" && ./scripts/config-init.sh >/dev/null 2>&1 )
igual "un stack fuera de la composición no bootstrapea" "1" \
  "$([ -f "$ROOT/runtime/desarrollo/config/dnsmasq/dnsmasq.conf" ]; echo $?)"

# --- Sin composición legible ---

rm -f "$STUB_DIR/servicios"
: > "$STUB_DIR/servicios"
sale_con "sin composición legible aborta" 1 bash -c "cd '$ROOT' && ./scripts/config-init.sh"

# =====================================================================
titulo "timers.sh — qué units corresponden y con qué nombre"
# =====================================================================

# Checkout con las plantillas reales: lo que se afirma abajo es lo que queda
# instalado de verdad, no una copia de las units dentro del test.

crear_root_timers() {
  local root proyecto="$1" entorno="$2"
  root=$(crear_root "timers-$proyecto" timers.sh)
  mkdir -p "$root/host/systemd" "$root/stacks" "$root/systemd"
  cp "$REPO_ROOT"/host/systemd/* "$root/host/systemd/"
  cp -R "$REPO_ROOT"/stacks/backup "$REPO_ROOT"/stacks/certbot "$root/stacks/"
  printf 'COMPOSE_PROJECT_NAME=%s\nPUBLIC_HOSTNAME=odoo.example.test\nODOO_EDITION=community\nTAG=19.0-ce-2026-09-16\n' \
    "$proyecto" > "$root/runtime/$entorno/compose.env"
  printf '%s' "$entorno" > "$root/.entorno-prueba"
  printf '%s' "$root"
}

timers() {
  local entorno; entorno=$(cat "$1/.entorno-prueba")
  (cd "$1" && ENTORNO="$entorno" SYSTEMD_DIR="$1/systemd" ./scripts/timers.sh "$2" 2>&1)
}

# --- Producción: respalda y renueva ---

ROOT=$(crear_root_timers production produccion)
reset_stub
printf 'postgres\nodoo\nbackup\ncertbot\n' > "$STUB_DIR/servicios"

UNIDADES=$(timers "$ROOT" units); UNIDADES_CODIGO=$?
igual "el parser de units termina correctamente" "0" "$UNIDADES_CODIGO"
igual "las tres units, prefijadas por el proyecto" \
  "production-backup-daily production-backup-monthly production-cert-renew" \
  "$(printf '%s\n' "$UNIDADES" | tr '\n' ' ' | sed 's/ $//')"
igual "y la plantilla de aviso" "production-notify@" "$(timers "$ROOT" notify)"

SALIDA=$(timers "$ROOT" install)
igual "instala los siete archivos" "7" "$(ls "$ROOT/systemd" | wc -l | tr -d ' ')"
contiene "activa los timers con el nombre prefijado" \
  "systemctl enable --now production-backup-daily.timer production-backup-monthly.timer production-cert-renew.timer" \
  "$(llamadas)"
contiene "y recarga systemd antes" "systemctl daemon-reload" "$(llamadas)"

# Los dos reemplazos que la plantilla no puede traer resueltos.
no_contiene "no queda el marcador de ruta" "CAMBIAR-en-deploy" "$(cat "$ROOT/systemd/production-backup-daily.service")"
contiene    "la ruta es la del checkout"   "WorkingDirectory=$ROOT" "$(cat "$ROOT/systemd/production-backup-daily.service")"
contiene    "la unit fija el runtime de producción" "Environment=ENTORNO=produccion" "$(cat "$ROOT/systemd/production-backup-daily.service")"
contiene    "el OnFailure apunta a la plantilla de ESTE stack" \
  "OnFailure=production-notify@%n.service" "$(cat "$ROOT/systemd/production-cert-renew.service")"

# --- Unit con prefijo legado ---
# Comparte checkout con producción y se conserva para revisión del operador.

: > "$ROOT/systemd/odoo-backup-daily.timer"
printf 'WorkingDirectory=%s\n' "$ROOT" > "$ROOT/systemd/odoo-backup-daily.service"
reset_stub
SALIDA=$(timers "$ROOT" install)
contiene "avisa una unit heredada del mismo checkout" \
  "unit de otro proyecto apunta a este checkout: odoo-backup-daily.service" "$SALIDA"
no_contiene "no desactiva la unit heredada" "disable --now odoo-backup-daily.timer" "$(llamadas)"
igual "y conserva sus archivos para revisión" "0" \
  "$([ -f "$ROOT/systemd/odoo-backup-daily.service" ] && [ -f "$ROOT/systemd/odoo-backup-daily.timer" ]; echo $?)"

# --- Staging: no respalda, pero sí renueva ---
# El agujero que este target cierra: staging quedaba sin ninguna unit instalada.

ROOT_STAG=$(crear_root_timers staging staging)
reset_stub
printf 'postgres\nodoo\ncertbot\n' > "$STUB_DIR/servicios"

igual "sin capa de backups, solo la del certificado" \
  "staging-cert-renew" "$(timers "$ROOT_STAG" units | tr '\n' ' ' | sed 's/ $//')"

timers "$ROOT_STAG" install >/dev/null
contiene "la unit fija el runtime de staging" "Environment=ENTORNO=staging" \
  "$(cat "$ROOT_STAG/systemd/staging-cert-renew.service")"

# --- El checkout que perdió una capa ---
# La unit vieja sigue enabled y dispara igual: sin removerla, backup.sh corre de
# madrugada contra un stack que ya no incluye la capa de backups.

reset_stub
printf 'postgres\nodoo\ncertbot\n' > "$STUB_DIR/servicios"
: > "$ROOT_STAG/systemd/staging-backup-daily.timer"
: > "$ROOT_STAG/systemd/staging-backup-daily.service"

SALIDA=$(timers "$ROOT_STAG" install)
contiene    "desactiva la unit que dejó de corresponder" \
  "systemctl disable --now staging-backup-daily.timer" "$(llamadas)"
no_contiene "y borra sus dos archivos" "staging-backup-daily" "$(ls "$ROOT_STAG/systemd")"
igual "instala tres archivos, no siete" "3" "$(ls "$ROOT_STAG/systemd" | wc -l | tr -d ' ')"
no_contiene "y no toca las units del otro checkout" "production-" "$(ls "$ROOT_STAG/systemd")"

# --- El checkout vecino cuyo nombre empieza igual ---
# El glob del prefijo no distingue 'staging-' de 'staging-qa-': sin cruzar el
# resto contra las bases conocidas, este install desactivaba y borraba las units
# del otro deployment, que es exactamente lo que el prefijo existe para evitar.

reset_stub
printf 'postgres\nodoo\ncertbot\n' > "$STUB_DIR/servicios"
: > "$ROOT_STAG/systemd/staging-qa-cert-renew.timer"
: > "$ROOT_STAG/systemd/staging-qa-cert-renew.service"

SALIDA=$(timers "$ROOT_STAG" install)
contiene    "deja en pie las units del vecino con prefijo compartido" \
  "staging-qa-cert-renew.timer" "$(ls "$ROOT_STAG/systemd")"
no_contiene "y no las desactiva" "disable --now staging-qa" "$(llamadas)"

# --- Development: ni una ---

ROOT_DEV=$(crear_root_timers development-sale desarrollo)
reset_stub
printf 'postgres\nodoo\nnginx\n' > "$STUB_DIR/servicios"

SALIDA=$(timers "$ROOT_DEV" install)
igual       "no instala nada" "0" "$(ls "$ROOT_DEV/systemd" | wc -l | tr -d ' ')"
contiene    "y dice por qué" "no lleva units" "$SALIDA"
no_contiene "sin tocar systemd" "systemctl" "$(llamadas)"

# --- Sin composición legible ---
# Adivinar qué units corresponden es peor que no instalar ninguna.

reset_stub
: > "$STUB_DIR/servicios"
sale_con "sin composición legible aborta" 1 \
  bash -c "cd '$ROOT' && SYSTEMD_DIR='$ROOT/systemd' ./scripts/timers.sh install"

# --- Selector de imagen Odoo ---
# up y odoo-up deben detenerse antes de Compose si la referencia no es operativa.
ROOT_IMAGE=$(crear_root image-guard)
reset_stub
for target in up odoo-up; do
  sale_con "$target rechaza un selector inicial" 2 env ENTORNO=desarrollo \
    STUB_DIR="$STUB_DIR" PATH="$REPO_ROOT/tests/stubs:$PATH" \
    make -C "$ROOT_IMAGE" "$target"
done
igual "selector inválido no invoca Docker" "" "$(llamadas)"
contiene "Makefile expone la guarda de imagen" "require-odoo-image:" "$(cat "$REPO_ROOT/Makefile")"
no_contiene "Makefile no expone apply-image" "apply-image:" "$(cat "$REPO_ROOT/Makefile")"
no_contiene "Makefile no expone rollback-image" "rollback-image:" "$(cat "$REPO_ROOT/Makefile")"
no_contiene "la operación de módulos no exige Actual" "no hay imagen Actual" "$(cat "$REPO_ROOT/scripts/odoo-module-operation.sh")"

# La guarda debe cargar compose.env dentro de su propia receta: require-entorno
# corre en otro proceso y no puede dejar ODOO_IMAGE exportada para el siguiente.
ROOT_VALID=$(crear_root image-valid)
printf '%s\n' 'ODOO_IMAGE=local/odoo:19.0-desarrollo-20260918T112428Z-fa588059f4932d2f' >> "$ROOT_VALID/runtime/desarrollo/compose.env"
mkdir -p "$ROOT_VALID/fakebin"
cat > "$ROOT_VALID/fakebin/docker" <<'EOF'
#!/usr/bin/env bash
# Stub de Docker para comprobar la inspección de una imagen válida.
# No se ejecuta Compose: solo confirma que la guarda cargó ODOO_IMAGE.
printf '%s\n' "$*" >> "$STUB_DIR/llamadas"
case "$*" in
  *'image inspect local/odoo:'*) exit 0 ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$ROOT_VALID/fakebin/docker"
reset_stub
sale_con "la guarda acepta el selector cargado desde compose.env" 0 env ENTORNO=desarrollo \
  STUB_DIR="$STUB_DIR" PATH="$ROOT_VALID/fakebin:$PATH" \
  make -C "$ROOT_VALID" require-odoo-image
contiene "la guarda inspecciona la imagen seleccionada" "image inspect local/odoo:19.0-desarrollo-20260918T112428Z-fa588059f4932d2f" "$(llamadas)"

# =====================================================================
titulo "integrity-check, failure-notify y workspace — contratos de auxiliares"
# =====================================================================

# integrity-check debe pasar por el contexto del runtime y conservar el error del segundo comando.
ROOT_INT=$(crear_root integrity integrity-check.sh)
mkdir -p "$ROOT_INT/fakebin"
cat > "$ROOT_INT/fakebin/docker" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "$DOCKER_CALLS"
case "$*" in
  *postgres*) printf 'filestore/a\n' ;;
  *odoo*)
    cat >/dev/null
    if [ "${INTEGRITY_FAIL:-0}" -eq 1 ]; then
      printf 'FALTA: filestore/a\nreferenciados: 1 | faltantes: 1\n'
      exit 1
    fi
    printf 'referenciados: 1 | faltantes: 0\n'
    ;;
esac
EOF
chmod +x "$ROOT_INT/fakebin/docker"
SALIDA=$(cd "$ROOT_INT" && DOCKER_CALLS="$ROOT_INT/docker-calls" PATH="$ROOT_INT/fakebin:$PATH" \
  ENTORNO=staging ./scripts/integrity-check.sh 2>&1)
contiene "integrity-check usa el contexto" "integrity-check listo" "$SALIDA"
contiene "integrity-check pasa compose.env" \
  "--env-file $(cd "$ROOT_INT" && pwd -P)/runtime/staging/compose.env" "$(cat "$ROOT_INT/docker-calls")"
sale_con "integrity-check conserva un faltante" 1 env DOCKER_CALLS="$ROOT_INT/docker-calls-fail" \
  PATH="$ROOT_INT/fakebin:$PATH" ENTORNO=staging INTEGRITY_FAIL=1 \
  bash "$ROOT_INT/scripts/integrity-check.sh"

# failure-notify debe acotar el tiempo de red y devolver el error de curl.
ROOT_NOTIFY=$(crear_root notify failure-notify.sh)
mkdir -p "$ROOT_NOTIFY/runtime/produccion/secrets" "$ROOT_NOTIFY/fakebin"
printf 'smtp-password\n' > "$ROOT_NOTIFY/runtime/produccion/secrets/zeptomail_smtp_password"
cat >> "$ROOT_NOTIFY/runtime/produccion/compose.env" <<'EOF'
SMTP_HOST=smtp.example.test
SMTP_PORT=587
SMTP_USER=usuario
ALERT_EMAIL_FROM=alertas@example.test
ALERT_EMAIL_TO=ops@example.test
EOF
cat > "$ROOT_NOTIFY/fakebin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CALLS"
cat >/dev/null
exit "${CURL_FAIL:-0}"
EOF
chmod +x "$ROOT_NOTIFY/fakebin/curl"
SALIDA=$(cd "$ROOT_NOTIFY" && CURL_CALLS="$ROOT_NOTIFY/curl-calls" \
  PATH="$ROOT_NOTIFY/fakebin:$PATH" ENTORNO=produccion \
  ./scripts/failure-notify.sh backup.timer 2>&1)
contiene "failure-notify termina bien" "failure-notify listo" "$SALIDA"
contiene "failure-notify acota curl" "--connect-timeout 10 --max-time 60" "$(cat "$ROOT_NOTIFY/curl-calls")"
sale_con "failure-notify conserva el error de red" 28 env CURL_CALLS="$ROOT_NOTIFY/curl-calls-fail" \
  PATH="$ROOT_NOTIFY/fakebin:$PATH" ENTORNO=produccion CURL_FAIL=28 \
  bash "$ROOT_NOTIFY/scripts/failure-notify.sh" backup.timer

# addons-runtime-init prepara los mounts antes de Compose y conserva el contrato de permisos.
# La fixture reemplaza solo el GID fijo por el grupo del test para ejercer el camino exitoso sin root.
ROOT_ADDONS_INIT="$TMP/addons-runtime-init"
GID_PRUEBA=$(id -g)
mkdir -p "$ROOT_ADDONS_INIT/scripts/lib"
cp scripts/lib/ui.sh "$ROOT_ADDONS_INIT/scripts/lib/"
sed "s/65532/$GID_PRUEBA/g" scripts/addons-runtime.sh > "$ROOT_ADDONS_INIT/scripts/addons-runtime.sh"
chmod +x "$ROOT_ADDONS_INIT/scripts/addons-runtime.sh"
SALIDA=$(cd "$ROOT_ADDONS_INIT" && ./scripts/addons-runtime.sh init 2>&1)
contiene "addons-runtime-init prepara desarrollo" "runtime/desarrollo/addons/custom listo" "$SALIDA"
contiene "addons-runtime-init prepara staging" "runtime/staging/addons/custom listo" "$SALIDA"
contiene "addons-runtime-init prepara producción" "runtime/produccion/addons/custom listo" "$SALIDA"
igual "addons-runtime-init aplica owner, grupo y 2775" "0" \
  "$(python3 - "$ROOT_ADDONS_INIT" "$GID_PRUEBA" <<'PY'
import os, stat, sys
root, gid = sys.argv[1], int(sys.argv[2])
expected_mode = 0o775 if sys.platform == 'darwin' else 0o2775
valid = all(
    (lambda value: value.st_uid == os.getuid() and value.st_gid == gid and stat.S_IMODE(value.st_mode) == expected_mode)(
        os.stat(os.path.join(root, 'runtime', environment, 'addons', 'custom'))
    )
    for environment in ('desarrollo', 'staging', 'produccion')
)
print(0 if valid else 1)
PY
)"
sale_con "addons-runtime-init es idempotente" 0 bash -c "cd '$ROOT_ADDONS_INIT' && ./scripts/addons-runtime.sh init"
chmod 0755 "$ROOT_ADDONS_INIT/runtime/staging/addons/custom"
SALIDA=$(cd "$ROOT_ADDONS_INIT" && ./scripts/addons-runtime.sh init 2>&1 || true)
contiene "addons-runtime-init diagnostica permisos incompatibles" \
  "sudo install -d -o $(id -u) -g $GID_PRUEBA -m 2775" "$SALIDA"

# El target del webhook no puede llegar a Docker si falla el bootstrap de mounts.
# Un entrypoint deliberadamente fallido permite observar el corte sin privilegios.
ROOT_WEBHOOK_INIT=$(crear_root webhook-init)
cp scripts/addons-runtime.sh "$ROOT_WEBHOOK_INIT/scripts/addons-runtime.sh"
cat > "$ROOT_WEBHOOK_INIT/scripts/addons-runtime.sh" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "$ROOT_WEBHOOK_INIT/scripts/addons-runtime.sh"
reset_stub
sale_con "addons-webhook-up corta si falla addons-runtime-init" 2 env ENTORNO=produccion \
  STUB_DIR="$STUB_DIR" PATH="$REPO_ROOT/tests/stubs:$PATH" \
  make -C "$ROOT_WEBHOOK_INIT" addons-webhook-up
igual "el bootstrap fallido ocurre antes de Docker" "" "$(llamadas)"

# El lifecycle de Odoo recrea bajo lock y nunca traduce restart a docker compose restart.
# Un preflight fallido debe cortar antes de cualquier llamada al stub de Docker.
ROOT_LIFECYCLE=$(crear_root lifecycle)
cp scripts/odoo-lifecycle.sh "$ROOT_LIFECYCLE/scripts/"
cp scripts/lib/candidate-lock.sh "$ROOT_LIFECYCLE/scripts/lib/"
cat > "$ROOT_LIFECYCLE/scripts/addons-runtime.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PREFLIGHT_CALLS"
exit "${PREFLIGHT_FAIL:-0}"
EOF
chmod +x "$ROOT_LIFECYCLE/scripts/odoo-lifecycle.sh" "$ROOT_LIFECYCLE/scripts/addons-runtime.sh"
reset_stub
sale_con "odoo-lifecycle recrea correctamente" 0 env ENTORNO=desarrollo \
  PREFLIGHT_CALLS="$ROOT_LIFECYCLE/preflight-calls" STUB_DIR="$STUB_DIR" \
  PATH="$REPO_ROOT/tests/stubs:$PATH" "$ROOT_LIFECYCLE/scripts/odoo-lifecycle.sh" restart
contiene "odoo-lifecycle exige preflight" "preflight" "$(cat "$ROOT_LIFECYCLE/preflight-calls")"
contiene "odoo-lifecycle usa force-recreate" "up -d --force-recreate odoo" "$(llamadas)"
no_contiene "odoo-lifecycle no usa compose restart" " restart " "$(llamadas)"
no_contiene "odoo-lifecycle no construye imágenes" " build " "$(llamadas)"
igual "odoo-lifecycle usa el lock compartido" "0" \
  "$([ -f "$ROOT_LIFECYCLE/runtime/control/state/locks/environments/desarrollo.lock" ]; echo $?)"
LLAMADAS_ANTES=$(llamadas)
sale_con "odoo-lifecycle corta ante preflight incompatible" 1 env ENTORNO=desarrollo \
  PREFLIGHT_FAIL=1 PREFLIGHT_CALLS="$ROOT_LIFECYCLE/preflight-calls" STUB_DIR="$STUB_DIR" \
  PATH="$REPO_ROOT/tests/stubs:$PATH" "$ROOT_LIFECYCLE/scripts/odoo-lifecycle.sh" up
igual "preflight incompatible no llega a Compose" "$LLAMADAS_ANTES" "$(llamadas)"

TARGET_ODOO_RESTART=$(make -n ENTORNO=desarrollo odoo-restart 2>&1 || true)
contiene "odoo-restart delega en el lifecycle" "scripts/odoo-lifecycle.sh restart" "$TARGET_ODOO_RESTART"
TARGET_NGINX_RESTART=$(make -n ENTORNO=desarrollo nginx-restart 2>&1 || true)
contiene "otros stacks conservan compose restart" "restart nginx" "$TARGET_NGINX_RESTART"

# El workspace expone solo candidatos del entorno y no modifica la configuración del usuario.
ROOT_WS=$(crear_root workspace vscode-workspace.sh)
mkdir -p "$ROOT_WS/runtime/staging/addons/custom"
SALIDA=$(cd "$ROOT_WS" && ENTORNO=staging ./scripts/vscode-workspace.sh 2>&1)
contiene "workspace genera el archivo" "workspace-staging.code-workspace" "$SALIDA"
contiene "workspace usa los candidatos del entorno" "runtime/staging/addons/custom" \
  "$(cat "$ROOT_WS/workspace-staging.code-workspace")"
no_contiene "workspace no vuelve a addons raíz" '"path": "'$ROOT_WS'/addons"' \
  "$(cat "$ROOT_WS/workspace-staging.code-workspace")"
no_contiene "workspace no muestra clones bare" 'runtime/addons/.repos' \
  "$(cat "$ROOT_WS/workspace-staging.code-workspace")"
no_contiene "workspace no muestra builds" 'runtime/addons/builds' \
  "$(cat "$ROOT_WS/workspace-staging.code-workspace")"
igual "workspace no escribe configuración auxiliar" "0" \
  "$([ ! -e "$ROOT_WS/.vscode/settings.json" ] && [ ! -e "$ROOT_WS/runtime/addons/.vscode/settings.json" ]; echo $?)"
TARGET_WORKSPACE=$(make -n ENTORNO=staging workspace 2>&1)
contiene "workspace usa el selector de entorno" "scripts/lib/contexto.sh validar" "$TARGET_WORKSPACE"
contiene "workspace ejecuta su generador" "scripts/vscode-workspace.sh" "$TARGET_WORKSPACE"
sale_con "workspace sin candidatos explica cómo sincronizar" 1 \
  bash -c "cd '$ROOT_WS' && rm -rf runtime/staging/addons/custom && ENTORNO=staging ./scripts/vscode-workspace.sh"

mkdir -p "$ROOT_WS/runtime/produccion/addons/custom" "$ROOT_WS/runtime/produccion/addons/enterprise"
sed -i.bak 's/ODOO_EDITION=community/ODOO_EDITION=enterprise/; s/19.0-ce/19.0-ee/' \
  "$ROOT_WS/runtime/produccion/compose.env"
SALIDA=$(cd "$ROOT_WS" && ENTORNO=produccion ./scripts/vscode-workspace.sh 2>&1)
contiene "workspace Enterprise incluye su checkout" 'runtime/produccion/addons/enterprise' \
  "$(cat "$ROOT_WS/workspace-produccion.code-workspace")"

resumen
