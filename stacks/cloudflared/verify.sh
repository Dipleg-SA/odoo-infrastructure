#!/usr/bin/env bash
# Qué se espera del stack cloudflared. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_cloudflared() {
  titulo "cloudflared"

  sano cloudflared

  # --- Conexiones del túnel ---
  # Cuatro registradas es lo normal; una sola funciona pero está degradado, y es
  # el estado que precede a una caída sin que nada más lo muestre.

  local conns
  if ! corriendo cloudflared; then
    omitir "cloudflared con >=2 conexiones" "$(motivo cloudflared)"
  else
    conns=$(docker compose logs cloudflared 2>/dev/null | grep -c "Registered tunnel connection")
    if [ "${conns:-0}" -ge 2 ]; then ok "cloudflared con $conns conexiones registradas"
    elif [ "${conns:-0}" -eq 1 ]; then aviso "cloudflared con >=2 conexiones" "solo 1 — degradado"
    else bad "cloudflared con >=2 conexiones" "0 — el Tunnel no conecta"; fi
  fi

  # --- Binds ---
  # El túnel sale hacia afuera: no publica nada, y las métricas son internas.

  sin_publicar cloudflared 2000
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_cloudflared
resumen
