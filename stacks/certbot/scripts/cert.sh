#!/usr/bin/env bash
# Certificados de Let's Encrypt por DNS-01. issue emite la primera vez, renew
# corre por timer y recarga nginx. Sin dependencias fuera de docker compose.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh

# --- Entorno ---
# Como el resto de los scripts: los valores por deployment salen de .env, nunca
# de la shell del operador, para que el timer de systemd vea exactamente lo mismo.

if [ -f .env ]; then set -a; . ./.env; set +a; fi

: "${PUBLIC_HOSTNAME:?falta en .env — sin hostname no hay certificado que emitir}"

certbot() { docker compose --profile cert run --rm -T certbot "$@"; }

# --- Métrica de vencimiento ---
# Única fuente de la alerta de vencimiento. Mide lo que certbot tiene en disco,
# no lo que nginx está sirviendo: el caso "renovó y nadie recargó" lo cubren el
# reload de abajo y el chequeo contra el socket real de odoo-verify.

escribir_metrica() {
  local dir="state/textfile" tmp fin epoch
  fin=$(certbot certificates 2>/dev/null | sed -n 's/.*Expiry Date: \([^ ]* [^ ]*\).*/\1/p' | head -1)
  [ -n "$fin" ] || { ui_warn "no se pudo leer la fecha de vencimiento" "sin métrica" >&2; return 0; }
  epoch=$(date -u -d "$fin" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d %H:%M:%S' "$fin" +%s 2>/dev/null) || {
    ui_warn "no se pudo convertir '$fin' a epoch" "sin métrica" >&2; return 0; }

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
    ui_warn "nginx no está corriendo" "no hay nada que recargar" >&2
    return 0
  fi
  docker compose exec -T nginx nginx -s reload
}

cmd_issue() {
  ui_plan_start "cert-issue"
  ui_step 1 "Emisión del certificado inicial para $PUBLIC_HOSTNAME."
  certbot certonly \
    --dns-cloudflare --dns-cloudflare-credentials /tmp/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 30 \
    -d "$PUBLIC_HOSTNAME" \
    --agree-tos --register-unsafely-without-email --non-interactive
  escribir_metrica

  ui_plan_end
  ui_ok "cert-issue listo — ya se puede levantar nginx"
  echo
}

# --- Renovación ---
# Los argumentos extra pasan a certbot: --force-renewal ejercita la cadena entera.

cmd_renew() {
  ui_plan_start "cert-renew"
  ui_step 1 "Renovación del certificado y recarga de nginx si está corriendo."
  certbot renew --non-interactive "$@"
  recargar_nginx
  escribir_metrica

  ui_plan_end
  ui_ok "cert-renew listo"
  echo
}

case "${1:-}" in
  issue) shift; cmd_issue "$@" ;;
  renew) shift; cmd_renew "$@" ;;
  *) ui_bad "uso: $(basename "$0") issue|renew" "" >&2; exit 2 ;;
esac
