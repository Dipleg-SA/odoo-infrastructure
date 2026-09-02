#!/usr/bin/env bash
# Qué se espera del stack certbot. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.
#
# No lleva `sano`: corre bajo profiles y nunca está levantado. Lo que se verifica
# es su producto —el certificado— y lo que necesita para producirlo: el token.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_certbot() {
  titulo "certbot"

  # --- Certificado ---
  # Lo emite certbot, no nginx: si falta, nginx ni siquiera arranca. Se avisa
  # antes de que el timer sea el que descubra el problema.

  local venc epoch ahora dias
  venc=$(docker compose --profile cert run --rm -T certbot certificates 2>/dev/null \
    | sed -n 's/.*Expiry Date: \([^ ]* [^ ]*\).*/\1/p' | head -1)
  if [ -z "$venc" ]; then
    bad "certificado emitido" "certbot no reporta ninguno — correr make cert-issue"
  else
    epoch=$(date -u -d "$venc" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d %H:%M:%S' "$venc" +%s 2>/dev/null || echo 0)
    ahora=$(date -u +%s); dias=$(( (epoch - ahora) / 86400 ))
    if [ "$epoch" -eq 0 ]; then aviso "certificado emitido" "no se pudo interpretar la fecha: $venc"
    elif [ "$dias" -lt 15 ]; then bad "certificado vigente" "vence en $dias días — la renovación no está corriendo"
    else ok "certificado vigente ($dias días)"; fi
  fi

  # --- Renovación automática ---
  # Sin el timer, la emisión inicial es la única que hubo: el certificado vence a
  # los 90 días y el chequeo de arriba lo descubre cuando faltan 15.

  timer_activo cert-renew

  # --- Token de Cloudflare ---
  # Valor y alcance de una sola vez, contra la API real. Lo consume certbot para
  # el desafío DNS-01: un token inválido no se nota hasta que el cert no renueva.
  #
  # /user/tokens/verify rechaza los tokens nuevos con prefijo cfut_ aunque sean
  # válidos — se prueba contra /zones, lo mismo que usa certbot de verdad.

  local token resp
  if token=$(cat secrets/cloudflare_api_token 2>/dev/null) && [ -n "$token" ]; then
    resp=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones"\n' \
      "$token" | curl -s -m 10 --config - 2>/dev/null)
    if printf '%s' "$resp" | grep -q '"success":true'; then
      if printf '%s' "$resp" | grep -q '"count":0'; then
        bad "token de Cloudflare activo" "token válido pero sin zonas visibles — revisá el alcance (Zone Resources) del token"
      else
        ok "token de Cloudflare activo"
      fi
    elif printf '%s' "$resp" | grep -q '"code":1000'; then
      bad "token de Cloudflare activo" "1000 Invalid API Token — el valor está mal pegado"
    elif printf '%s' "$resp" | grep -q '"code":9109'; then
      bad "token de Cloudflare activo" "9109 — el token no lee la zona; rehacerlo con la plantilla Edit zone DNS"
    else
      bad "token de Cloudflare activo" "respuesta inesperada de la API"
    fi
  else
    omitir "token de Cloudflare activo" "secret ilegible — correr con sudo"
  fi
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_certbot
resumen
