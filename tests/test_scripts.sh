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
  cp "$REPO_ROOT/scripts/lib/ui.sh" "$root/scripts/lib/"
  for s in "$@"; do cp "$REPO_ROOT/scripts/$s" "$root/scripts/"; done
  printf 'PUBLIC_HOSTNAME=odoo.example.test\n' > "$root/.env"
  printf '%s' "$root"
}

llamadas() { cat "$STUB_DIR/llamadas" 2>/dev/null; }
reset_stub() { : > "$STUB_DIR/llamadas"; rm -f "$STUB_DIR/config" "$STUB_DIR/ps-q" "$STUB_DIR/salida"; }

# =====================================================================
titulo "cert.sh — lo que le llega de verdad a certbot"
# =====================================================================

ROOT=$(crear_root cert cert.sh)
reset_stub
printf '  Expiry Date: 2026-11-01 12:00:00+00:00 (VALID: 80 days)\n' > "$STUB_DIR/salida"
printf 'idcontenedor\n' > "$STUB_DIR/ps-q"

(cd "$ROOT" && ./scripts/cert.sh renew --force-renewal >/dev/null 2>&1)

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
SALIDA=$( (cd "$ROOT" && ./scripts/cert.sh renew 2>&1) )
igual    "con nginx abajo igual sale con 0" "0" "$( (cd "$ROOT" && ./scripts/cert.sh renew >/dev/null 2>&1); echo $?)"
contiene "y lo avisa"                        "no está corriendo" "$SALIDA"

# --- Uso ---
sale_con "un subcomando inventado sale con 2" 2 bash "$ROOT/scripts/cert.sh" inventado

# =====================================================================
titulo "secrets-init.sh — la lista sale de la composición"
# =====================================================================

ROOT=$(crear_root secrets secrets-init.sh secrets-perms.sh)
reset_stub

# Lo que declara un entrypoint de development: tres, y los tres generables.
cat > "$STUB_DIR/config" <<'EOF'
secrets:
  odoo_admin_password:
    file: /repo/secrets/odoo_admin_password
  pgbouncer_credentials:
    file: /repo/secrets/pgbouncer_credentials
  postgres_password:
    file: /repo/secrets/postgres_password
EOF

SALIDA=$( (cd "$ROOT" && ./scripts/secrets-init.sh 2>&1) )
igual "crea exactamente los 3 declarados" "3" "$(ls "$ROOT/secrets" | wc -l | tr -d ' ')"
contiene "y dice cuáles omite"            "omitido (este stack no lo declara): secrets/cloudflare_api_token" "$SALIDA"
contiene "sin dejar nada pendiente"       "Todos los secrets tienen valor" "$SALIDA"

# hex y no base64: los / + = rompen a cualquier consumidor que arme una URI.
igual "genera 64 hex" "0" \
  "$(grep -qE '^[0-9a-f]{64}$' "$ROOT/secrets/postgres_password"; echo $?)"

# El userlist de PgBouncer lleva el MISMO valor que el password.
contiene "el userlist de pgbouncer deriva del password" \
  "$(cat "$ROOT/secrets/postgres_password")" "$(cat "$ROOT/secrets/pgbouncer_credentials")"

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
rm -f "$ROOT/secrets/postgres_password" "$ROOT/secrets/pgbouncer_credentials" "$ROOT/secrets/odoo_admin_password"

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

resumen
