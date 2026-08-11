#!/usr/bin/env bash
# Crea config/traefik/acme.json, lo único de config/ que no se versiona: es
# estado de runtime, no configuración. Idempotente. Paso 1 de un deploy nuevo.
set -euo pipefail

cd "$(dirname "$0")/.."

# --- acme.json ---
# Si no existe como ARCHIVO antes del primer up, Docker lo bind-montea creando un directorio y el cert nunca persiste.

ACME=config/traefik/acme.json

if [ ! -e "$ACME" ]; then
  install -m 600 /dev/null "$ACME"
  echo "creado: $ACME"
elif [ -d "$ACME" ]; then
  cat >&2 <<EOF
ATENCION: $ACME es un directorio, no un archivo — Docker lo creó así porque
faltaba al primer 'docker compose up'. Traefik no puede persistir el certificado.
Recrear con:
  docker compose stop traefik
  sudo rm -rf $ACME && install -m 600 /dev/null $ACME
  docker compose up -d --force-recreate traefik
EOF
  exit 1
else
  echo "skip (ya existe): $ACME"
fi
