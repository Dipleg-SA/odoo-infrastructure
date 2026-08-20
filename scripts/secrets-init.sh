#!/usr/bin/env bash
# Crea el esqueleto de secrets/: genera los derivables y deja plantillas con el
# marcador CAMBIAR para los que se pegan a mano. Idempotente — nunca pisa nada.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

# --- Umask ---
# Lo que se cree acá nace 600; secrets-perms le pone 640 y el grupo consumidor.

umask 077
mkdir -p secrets

MARK="CAMBIAR"
creados=()

# --- Qué secrets lleva ESTE stack ---
# Se lo pregunta a la composición, como las guardas del Makefile: cada entrypoint
# ya declara los suyos —11 producción, 8 staging, 3 development— y una segunda
# lista acá divergiría. Sin esto, un stack chico nace con archivos inertes que
# secrets-check después exige completar.

DECLARADOS=$(docker compose --profile cert --profile restore config 2>/dev/null \
  | sed -n 's|^ *file: .*/secrets/\([a-z0-9_]*\)$|\1|p')

if [ -z "$DECLARADOS" ]; then
  ui_bad "no se pudo leer los secrets de la composición" "revisar COMPOSE_FILE en .env" >&2
  exit 1
fi

ui_start "secrets-init"

# --- Helper ---
# Escribe solo si el archivo no existe y este stack lo declara; stdin trae el contenido.

nuevo() {
  if ! printf '%s\n' "$DECLARADOS" | grep -qx "$1"; then
    ui_skip "omitido (este stack no lo declara): secrets/$1"
    return 1
  fi
  if [ -e "secrets/$1" ]; then
    ui_skip "skip (ya existe): secrets/$1"
    return 1
  fi
  cat > "secrets/$1"
  ui_ok "creado: secrets/$1"
  creados+=("$1")
  return 0
}

# --- Generador ---
# hex y no base64: los / + = de base64 rompen cualquier consumidor que arme una URI
# con la credencial adentro (lo encontró el exporter de Postgres en su momento).
# 32 bytes = 256 bits, misma entropía que antes.

genpass() { openssl rand -hex 32 | tr -d '\n'; }

# --- Password de Postgres y su userlist ---
# El userlist de PgBouncer lleva el MISMO valor; se deriva del archivo, así que
# sigue coincidiendo aunque postgres_password ya existiera de una corrida previa.

nuevo postgres_password < <(genpass) || true
nuevo pgbouncer_credentials < <(printf '"odoo" "%s"' "$(cat secrets/postgres_password)") || true

# --- Master password de Odoo ---

nuevo odoo_admin_password < <(genpass) || true

# --- Password de admin de Grafana ---
# Derivable: es credencial, pero no viene de un tercero, así que no exige paso manual.

nuevo grafana_admin_password < <(genpass) || true

# --- Password del rol de monitoreo de Postgres ---
# Rol propio de solo lectura (pg_monitor): el agente que tiene el socket de Docker
# y los logs no porta la credencial de la aplicación. El rol se crea en levantar-produccion.md.

nuevo postgres_exporter_password < <(genpass) || true

# --- Valores que se pegan a mano ---
# Un solo valor opaco por archivo: el consumidor lee el archivo entero.

for s in cloudflare_api_token cloudflare_tunnel_token zeptomail_smtp_password restic_password; do
  nuevo "$s" < <(printf '%s' "$MARK") || true
done

# --- Credenciales de R2 ---
# La misma clave va en los dos, en sintaxis distinta: pgBackRest parsea su INI y
# restic el formato de AWS. Al rotarla hay que tocar ambos.

nuevo pgbackrest_r2_credentials <<EOF || true
[global]
repo1-s3-key=$MARK
repo1-s3-key-secret=$MARK
repo1-cipher-pass=$MARK
EOF

nuevo restic_r2_credentials <<EOF || true
[default]
aws_access_key_id=$MARK
aws_secret_access_key=$MARK
EOF

# --- Resumen ---
# Solo lo que quedó con marcador necesita intervención antes de secrets-perms.

echo
pendientes=$(grep -rl "$MARK" secrets/ 2>/dev/null | sed 's|secrets/||' | sort || true)
if [ -n "$pendientes" ]; then
  ui_warn "Falta cargar el valor real en:" ""
  printf '  %s\n' $pendientes
  echo
  echo "Después: sudo make secrets-perms && make secrets-check"
else
  ui_ok "Todos los secrets tienen valor. Seguir con: sudo make secrets-perms"
fi
