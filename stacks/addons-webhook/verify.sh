#!/usr/bin/env bash
# Qué se espera del receptor de candidatos.
# La composición resuelta es la fuente de verdad para sus límites.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

servicio_addons_webhook() {
  contexto_compose config 2>/dev/null | awk '
    /^services:$/ { servicios = 1; next }
    servicios && /^  [^ ]/ {
      if ($0 == "  addons-webhook:") { encontrado = 1; dentro = 1; next }
      if (dentro) exit
      next
    }
    dentro { print }
    END { if (!encontrado) exit 1 }
  '
}

sin_referencias_prohibidas() {
  local nombre="$1" patron="$2" configuracion="$3"
  if printf '%s\n' "$configuracion" | grep -Eiq "$patron"; then
    bad "$nombre" "la composición del receptor contiene una referencia prohibida"
  else
    ok "$nombre"
  fi
}

v_addons_webhook() {
  titulo "addons-webhook"
  sano addons-webhook

  local configuracion
  if ! configuracion=$(servicio_addons_webhook) || [ -z "$configuracion" ]; then
    bad "configuración aislada del receptor" "no se pudo leer addons-webhook desde docker compose config"
    return
  fi

  sin_referencias_prohibidas "sin acceso a Docker" \
    'docker\.sock|DOCKER_HOST|docker[[:space:]_-]*api' "$configuracion"
  sin_referencias_prohibidas "sin recursos de Odoo, Postgres, filestore ni Enterprise" \
    'DOCKER_API|POSTGRES_[A-Z_]+:|DB_(HOST|USER|NAME|PASSWORD):|/var/lib/(odoo|postgres|postgresql)|/data/odoo|filestore|enterprise' "$configuracion"
  sin_referencias_prohibidas "sin secretos de Odoo" \
    'odoo_admin_password|postgres_password|zeptomail_smtp_password|admin_passwd|smtp_password' "$configuracion"
  sin_referencias_prohibidas "sin referencia a la imagen de Odoo" \
    '^[[:space:]]*image:|ODOO_IMAGE' "$configuracion"
  if grep -Eiq '^[[:space:]]*FROM[[:space:]]+odoo|enterprise' stacks/addons-webhook/image/Dockerfile; then
    bad "la imagen del receptor no deriva de Odoo ni contiene Enterprise" "Dockerfile con base o contenido prohibido"
  else
    ok "la imagen del receptor no deriva de Odoo ni contiene Enterprise"
  fi

  local cantidad_secretos
  cantidad_secretos=$(printf '%s\n' "$configuracion" | grep -Ec '^[[:space:]]*target: /run/secrets/[^/]+$' || true)
  if [ "$cantidad_secretos" -eq 4 ] \
    && ! printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*target: /run/secrets$|^[[:space:]]*source: .*/runtime/control/secrets$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*target: /run/secrets/addons_webhook_secret$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*target: /run/secrets/git_readonly_token$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*target: /run/secrets/git_readonly_key$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*target: /run/secrets/git_known_hosts$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*source: .*/runtime/control/secrets/addons_webhook_secret$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*source: .*/runtime/control/secrets/git_readonly_token$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*source: .*/runtime/control/secrets/git_readonly_key$' \
    && printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*source: .*/runtime/control/secrets/git_known_hosts$'; then
    ok "solo monta los cuatro secretos dedicados al webhook"
  else
    bad "solo monta los cuatro secretos dedicados al webhook" "los montajes de /run/secrets no coinciden con la allowlist"
  fi

  if printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*-[[:space:]]*edge$' \
    && ! printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*-[[:space:]]*(app|observability)$' \
    && ! printf '%s\n' "$configuracion" | grep -Eq '^[[:space:]]*ports:'; then
    ok "red edge sin puertos publicados"
  else
    bad "red edge sin puertos publicados" "el receptor sale de edge o publica puertos"
  fi
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_addons_webhook
resumen
