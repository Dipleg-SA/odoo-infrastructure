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

# --- Checkout falso ---
# Solo los directorios que el script toca; el .env, porque los tres leen de ahí.

crear_root() {
  local root="$TMP/$1"; shift
  mkdir -p "$root/scripts/lib" "$root/state/textfile" "$root/secrets"
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$REPO_ROOT/scripts/lib/compose.sh" "$root/scripts/lib/"
  for s in "$@"; do cp "$REPO_ROOT/scripts/$s" "$root/scripts/"; done
  printf 'PUBLIC_HOSTNAME=odoo.example.test\n' > "$root/.env"
  printf '%s' "$root"
}

llamadas() { cat "$STUB_DIR/llamadas" 2>/dev/null; }
reset_stub() { : > "$STUB_DIR/llamadas"; rm -f "$STUB_DIR/config" "$STUB_DIR/ps-q" "$STUB_DIR/salida"; }

# =====================================================================
titulo "cert.sh — lo que le llega de verdad a certbot"
# =====================================================================

ROOT=$(crear_root cert)
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

METRICA=$(cat "$ROOT/state/textfile/cert.prom" 2>/dev/null)
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
igual "crea exactamente los 2 declarados" "2" "$(ls "$ROOT/secrets" | wc -l | tr -d ' ')"
contiene "y dice cuáles omite"            "omitido (este stack no lo declara): secrets/cloudflare_api_token" "$SALIDA"
contiene "sin dejar nada pendiente"       "Todos los secrets tienen valor" "$SALIDA"

# hex y no base64: los / + = rompen a cualquier consumidor que arme una URI.
igual "genera 64 hex" "0" \
  "$(grep -qE '^[0-9a-f]{64}$' "$ROOT/secrets/postgres_password"; echo $?)"

# --- Idempotencia ---
# Se corre de nuevo en cada checkout que suma una capa: pisar un valor cargado
# sería irrecuperable para los que no se generan.

ANTES=$(cat "$ROOT/secrets/postgres_password")
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-init.sh 2>&1) )
igual    "no pisa un valor ya cargado" "$ANTES" "$(cat "$ROOT/secrets/postgres_password")"
contiene "y lo dice"                   "skip (ya existe)" "$SALIDA"

# --- Sin composición ---
# Sin saber qué declara el stack, crear los once sería fabricar archivos inertes.

rm -f "$STUB_DIR/config"
sale_con "sin composición legible aborta" 1 bash -c "cd '$ROOT' && ./scripts/secrets-init.sh"

# =====================================================================
titulo "secrets-perms.sh --check"
# =====================================================================

# postgres_exporter_password lo lee alloy, que corre como root: es el único sin GID
# exigido, así que se puede probar el resto de la lógica sin ser root.

printf 'valor\n' > "$ROOT/secrets/postgres_exporter_password"
chmod 640 "$ROOT/secrets/postgres_exporter_password"
rm -f "$ROOT/secrets/postgres_password" "$ROOT/secrets/odoo_admin_password"

sale_con "un secret en 640 pasa" 0 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"

chmod 600 "$ROOT/secrets/postgres_exporter_password"
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-perms.sh --check 2>&1) )
sale_con "un 600 no pasa" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"
contiene "y nombra el modo que encontró" "permisos 600, esperado 640" "$SALIDA"

# El marcador es lo que separa "el archivo existe" de "el valor está cargado".
chmod 640 "$ROOT/secrets/postgres_exporter_password"
printf 'CAMBIAR' > "$ROOT/secrets/postgres_exporter_password"
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-perms.sh --check 2>&1) )
sale_con "un marcador sin reemplazar no pasa" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"
contiene "y lo nombra"                        "todavía tiene el marcador" "$SALIDA"

# --- El GID ---
# Sin root no se puede poner el grupo esperado, pero sí probar que lo exige: el
# archivo nace con el grupo del que corre el test, que nunca es el 65532 de cloudflared.

printf 'valor\n' > "$ROOT/secrets/postgres_exporter_password"
printf 'token\n' > "$ROOT/secrets/cloudflare_tunnel_token"
chmod 640 "$ROOT/secrets/cloudflare_tunnel_token"
SALIDA=$( (cd "$ROOT" && ./scripts/secrets-perms.sh --check 2>&1) )
sale_con "un grupo que no es el del consumidor no pasa" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"
contiene "y nombra el GID esperado" "esperado 65532" "$SALIDA"

rm -rf "$ROOT/secrets"
sale_con "sin secrets/ aborta" 1 bash -c "cd '$ROOT' && ./scripts/secrets-perms.sh --check"

# =====================================================================
titulo "config-init.sh — qué stack está activo decide qué bootstrapea"
# =====================================================================

ROOT=$(crear_root config config-init.sh)
reset_stub

# Dos stacks activos, uno con dos .example (uno anidado) y otro sin config/ propia.
mkdir -p "$ROOT/stacks/nginx/config" "$ROOT/stacks/grafana/config/provisioning/alerting" "$ROOT/addons"
printf 'default;\n' > "$ROOT/stacks/nginx/config/00-http.conf.example"
printf 'de-mas;\n' > "$ROOT/stacks/nginx/config/odoo.locations.example"
printf 'TU_EMAIL_ALERTA_TO\n' > "$ROOT/stacks/grafana/config/provisioning/alerting/contact-points.yaml.example"
printf 'odoo.txt\n' > "$ROOT/addons/addons.txt.example"
printf 'requirements\n' > "$ROOT/addons/requirements.txt.example"
printf '%s\n' 'nginx' 'grafana' > "$STUB_DIR/servicios"

SALIDA=$( (cd "$ROOT" && ./scripts/config-init.sh 2>&1) )
igual "crea los 2 de nginx"        "0" "$([ -f "$ROOT/stacks/nginx/config/00-http.conf" ] && [ -f "$ROOT/stacks/nginx/config/odoo.locations" ]; echo $?)"
igual "y el anidado de grafana"    "0" "$([ -f "$ROOT/stacks/grafana/config/provisioning/alerting/contact-points.yaml" ]; echo $?)"
igual "sin odoo, sin addons" "" "$(ls "$ROOT/addons" 2>/dev/null | grep -v example || true)"

# --- Idempotencia: no pisa lo cargado a mano ---

printf 'editado a mano\n' > "$ROOT/stacks/nginx/config/00-http.conf"
SALIDA=$( (cd "$ROOT" && ./scripts/config-init.sh 2>&1) )
igual    "no pisa un archivo ya cargado" "editado a mano" "$(cat "$ROOT/stacks/nginx/config/00-http.conf")"
contiene "y lo dice"                     "skip (ya existe)" "$SALIDA"

# --- Odoo activo: addons entra ---

printf '%s\n' 'nginx' 'grafana' 'odoo' > "$STUB_DIR/servicios"
SALIDA=$( (cd "$ROOT" && ./scripts/config-init.sh 2>&1) )
igual "bootstrapea los 2 de addons" "0" \
  "$([ -f "$ROOT/addons/addons.txt" ] && [ -f "$ROOT/addons/requirements.txt" ]; echo $?)"

# --- Un stack ausente no deja rastro ---
# dnsmasq no está entre los activos: su .example no se toca.

mkdir -p "$ROOT/stacks/dnsmasq/config"
printf 'TU_IP_LOCAL\n' > "$ROOT/stacks/dnsmasq/config/dnsmasq.conf.example"
( cd "$ROOT" && ./scripts/config-init.sh >/dev/null 2>&1 )
igual "un stack fuera de la composición no bootstrapea" "1" \
  "$([ -f "$ROOT/stacks/dnsmasq/config/dnsmasq.conf" ]; echo $?)"

# --- Sin composición legible ---

rm -f "$STUB_DIR/servicios"
sale_con "sin composición legible aborta" 1 bash -c "cd '$ROOT' && ./scripts/config-init.sh"

# =====================================================================
titulo "timers.sh — qué units corresponden y con qué nombre"
# =====================================================================

# Checkout con las plantillas reales: lo que se afirma abajo es lo que queda
# instalado de verdad, no una copia de las units dentro del test.

crear_root_timers() {
  local root proyecto="$1"
  root=$(crear_root "timers-$proyecto" timers.sh)
  mkdir -p "$root/host/systemd" "$root/stacks" "$root/systemd"
  cp "$REPO_ROOT"/host/systemd/* "$root/host/systemd/"
  cp -R "$REPO_ROOT"/stacks/backup "$REPO_ROOT"/stacks/certbot "$root/stacks/"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "$proyecto" >> "$root/.env"
  printf '%s' "$root"
}

timers() { (cd "$1" && SYSTEMD_DIR="$1/systemd" ./scripts/timers.sh "$2" 2>&1); }

# --- Producción: respalda y renueva ---

ROOT=$(crear_root_timers production)
reset_stub
printf 'postgres\nodoo\nbackup\ncertbot\n' > "$STUB_DIR/servicios"

igual "las tres units, prefijadas por el proyecto" \
  "production-backup-daily production-backup-monthly production-cert-renew" \
  "$(timers "$ROOT" units | tr '\n' ' ' | sed 's/ $//')"
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
contiene    "el OnFailure apunta a la plantilla de ESTE stack" \
  "OnFailure=production-notify@%n.service" "$(cat "$ROOT/systemd/production-cert-renew.service")"

# --- Staging: no respalda, pero sí renueva ---
# El agujero que este target cierra: staging quedaba sin ninguna unit instalada.

ROOT_STAG=$(crear_root_timers staging)
reset_stub
printf 'postgres\nodoo\ncertbot\n' > "$STUB_DIR/servicios"

igual "sin capa de backups, solo la del certificado" \
  "staging-cert-renew" "$(timers "$ROOT_STAG" units | tr '\n' ' ' | sed 's/ $//')"

timers "$ROOT_STAG" install >/dev/null

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

# --- Development: ni una ---

ROOT_DEV=$(crear_root_timers development-sale)
reset_stub
printf 'postgres\nodoo\nnginx\n' > "$STUB_DIR/servicios"

SALIDA=$(timers "$ROOT_DEV" install)
igual       "no instala nada" "0" "$(ls "$ROOT_DEV/systemd" | wc -l | tr -d ' ')"
contiene    "y dice por qué" "no lleva units" "$SALIDA"
no_contiene "sin tocar systemd" "systemctl" "$(llamadas)"

# --- Sin composición legible ---
# Adivinar qué units corresponden es peor que no instalar ninguna.

reset_stub
rm -f "$STUB_DIR/servicios"
sale_con "sin composición legible aborta" 1 \
  bash -c "cd '$ROOT' && SYSTEMD_DIR='$ROOT/systemd' ./scripts/timers.sh install"

resumen
