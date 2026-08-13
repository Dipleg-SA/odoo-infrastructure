#!/usr/bin/env bash
# Certificados de Let's Encrypt por DNS-01. issue emite la primera vez, renew
# corre por timer y recarga nginx. Sin dependencias fuera de docker compose.
set -euo pipefail

cd "$(dirname "$0")/.."

# --- Entorno ---
# Como el resto de los scripts: los valores por deployment salen de .env, nunca
# de la shell del operador, para que el timer de systemd vea exactamente lo mismo.

if [ -f .env ]; then set -a; . ./.env; set +a; fi

: "${PUBLIC_HOSTNAME:?falta en .env — sin hostname no hay certificado que emitir}"

certbot() { docker compose --profile cert run --rm -T certbot "$@"; }

# --- Métrica de vencimiento ---
# Única fuente de la alerta de vencimiento. Mide lo que certbot tiene en disco,
# no lo que nginx está sirviendo: el caso "renovó y nadie recargó" lo cubren el
# reload de abajo y el chequeo contra el socket real de verify-odoo.

escribir_metrica() {
  local dir="state/textfile" tmp fin epoch
  fin=$(certbot certificates 2>/dev/null | sed -n 's/.*Expiry Date: \([^ ]* [^ ]*\).*/\1/p' | head -1)
  [ -n "$fin" ] || { echo "aviso: no se pudo leer la fecha de vencimiento — sin métrica" >&2; return 0; }
  epoch=$(date -u -d "$fin" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d %H:%M:%S' "$fin" +%s 2>/dev/null) || {
    echo "aviso: no se pudo convertir '$fin' a epoch — sin métrica" >&2; return 0; }

  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.cert.XXXXXX")
  {
    echo "# HELP odoo_cert_expiry_timestamp_seconds Vencimiento del certificado que tiene certbot en disco."
    echo "# TYPE odoo_cert_expiry_timestamp_seconds gauge"
    echo "odoo_cert_expiry_timestamp_seconds{host=\"$PUBLIC_HOSTNAME\"} $epoch"
  } > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$dir/cert.prom"
}

# --- Recarga de nginx ---
# Un certificado renovado que nginx no releyó sigue sirviendo el viejo hasta que
# vence. Best-effort: si nginx no está arriba no hay nada que recargar.

recargar_nginx() {
  if [ -z "$(docker compose ps -q nginx 2>/dev/null)" ]; then
    echo "aviso: nginx no está corriendo, no hay nada que recargar" >&2
    return 0
  fi
  docker compose exec -T nginx nginx -s reload
}

cmd_issue() {
  certbot certonly \
    --dns-cloudflare --dns-cloudflare-credentials /tmp/cloudflare.ini \
    --dns-cloudflare-propagation-seconds "${ACME_PROPAGATION_SECONDS:-30}" \
    -d "$PUBLIC_HOSTNAME" \
    --agree-tos --register-unsafely-without-email --non-interactive
  escribir_metrica
  echo "certificado emitido para $PUBLIC_HOSTNAME — ya se puede levantar nginx"
}

# --- Renovación ---
# Los argumentos extra pasan a certbot: --force-renewal ejercita la cadena entera.

cmd_renew() {
  certbot renew --non-interactive "$@"
  recargar_nginx
  escribir_metrica
}

case "${1:-}" in
  issue) shift; cmd_issue "$@" ;;
  renew) shift; cmd_renew "$@" ;;
  *) echo "uso: $(basename "$0") issue|renew" >&2; exit 2 ;;
esac
