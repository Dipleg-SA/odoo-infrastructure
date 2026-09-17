#!/usr/bin/env bash
# Qué se espera del stack certbot. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_certbot() {
  titulo "certbot"

  # --- Perfil declarable ---
  # Certbot corre como one-off, pero su fragmento debe existir en la composición.

  if perfil_declarado cert; then
    ok "perfil cert declarado"
  else
    bad "perfil cert declarado" "falta el fragmento de certbot en la composición"
    return
  fi

  # --- Certificado ---
  # La presencia y vigencia del certificado preceden al arranque de nginx.

  local venc epoch ahora dias
  venc=$(COMPOSE_PROFILES="${COMPOSE_PROFILES:+$COMPOSE_PROFILES,}cert" contexto_compose run --rm -T certbot certificates 2>/dev/null \
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
  # El timer evita que el certificado emitido quede vencido.

  timer_activo cert-renew

  # --- Token de Cloudflare ---
  # Se comprueba contra la API de zonas, que es el acceso requerido por DNS-01.

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
