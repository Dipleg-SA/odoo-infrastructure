#!/usr/bin/env bash
# Certificados de Let's Encrypt por DNS-01. issue emite la primera vez, renew
# corre por timer y recarga nginx. Sin dependencias fuera de docker compose.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
contexto_iniciar

: "${PUBLIC_HOSTNAME:?falta en runtime/$ENTORNO/compose.env}"

certbot() { COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}cert" contexto_compose run --rm -T certbot "$@"; }

# --- Métrica de vencimiento ---
# Mide el certificado que certbot tiene en disco y alimenta las alertas.

escribir_metrica() {
  local dir="$RUNTIME_STATE_DIR/textfile" tmp fin epoch
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
# Nginx relee el certificado renovado cuando está corriendo.

recargar_nginx() {
  if [ -z "$(contexto_compose ps -q nginx 2>/dev/null)" ]; then
    ui_warn "nginx no está corriendo" "no hay nada que recargar" >&2
    return 0
  fi
  contexto_compose exec -T nginx nginx -s reload
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
