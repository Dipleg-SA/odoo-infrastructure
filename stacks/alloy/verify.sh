#!/usr/bin/env bash
# Qué se espera del stack alloy. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

REGLAS=stacks/grafana/config/provisioning/alerting/rules.yaml
BACKUP_COMPOSE=stacks/backup/compose.yaml

# --- Cuántos componentes hay y cuántos no están sanos ---
# La API devuelve una línea con health.state por componente.

alloy_salud() {
  local comp="$1" total rotos
  total=$(printf '%s' "$comp" | grep -o '"health":{"state":"' | wc -l | tr -d ' ')
  rotos=$(printf '%s' "$comp" | grep -o '"health":{"state":"[a-z]*"' | grep -vc '"state":"healthy"' || true)
  printf '%s %s\n' "${total:-0}" "${rotos:-0}"
}

v_alloy() {
  titulo "alloy"

  sano alloy

  # --- Límite de privilegios ---
  # El agente necesita montajes de observabilidad, pero no privileged ni capacidades adicionales.

  local configuracion
  configuracion=$(contexto_compose config 2>/dev/null | awk '
    /^services:$/ { servicios = 1; next }
    servicios && /^  [^ ]/ {
      if ($0 == "  alloy:") { encontrado = 1; dentro = 1; next }
      if (dentro) exit
      next
    }
    dentro { print }
    END { if (!encontrado) exit 1 }
  ')
  if printf '%s\n' "$configuracion" | grep -qE '^    read_only: true$' \
    && printf '%s\n' "$configuracion" | grep -qE '^    cap_drop:$' \
    && printf '%s\n' "$configuracion" | grep -qE '^      - ALL$' \
    && printf '%s\n' "$configuracion" | grep -qE '^      - no-new-privileges:true$' \
    && ! printf '%s\n' "$configuracion" | grep -qE '^    privileged: true$|^    cap_add:'; then
    ok "alloy limita privilegios a observabilidad"
  else
    bad "alloy limita privilegios a observabilidad" \
      "exigir read_only, cap_drop=ALL, no-new-privileges y ningún privileged/cap_add"
  fi

  # --- Los componentes resuelven de verdad ---
  # La API en ejecución es la prueba de que las referencias resuelven.

  local comp rotos
  if ! corriendo alloy; then
    omitir "todos los componentes de Alloy sanos" "$(motivo alloy)"
  elif ! comp=$(contexto_compose exec -T alloy bash -c \
       'exec 3<>/dev/tcp/127.0.0.1/12345 && printf "GET /api/v0/web/components HTTP/1.0\r\n\r\n" >&3 && cat <&3' 2>/dev/null); then
    bad "todos los componentes de Alloy sanos" "no se pudo consultar la API de componentes"
  else
    local total
    read -r total rotos <<< "$(alloy_salud "$comp")"
    if [ "${total:-0}" -eq 0 ]; then
      bad "todos los componentes de Alloy sanos" "la API no devolvió ningún componente"
    elif [ "${rotos:-0}" -eq 0 ]; then
      ok "los $total componentes de Alloy sanos"
    else
      bad "todos los componentes de Alloy sanos" \
          "$rotos de $total en estado no-healthy — dejaron de emitir sin avisar"
    fi
  fi

  # --- Los dos umbrales de frescura del backup ---
  # La alerta debe avisar antes de que el healthcheck marque unhealthy.

  local alerta maxage
  alerta=$(sed -n 's/.*params: \[\([0-9]\{4,\}\)\].*/\1/p' "$REGLAS" 2>/dev/null | head -1)
  maxage=$(sed -n 's/.*RESTIC_MAX_AGE: \([0-9]*\)/\1/p' "$BACKUP_COMPOSE" 2>/dev/null | head -1)
  if ! declarado backup; then
    omitir "la alerta de backup avisa antes que el healthcheck" "este stack no respalda"
  elif [ -z "$alerta" ] || [ -z "$maxage" ]; then
    aviso "la alerta de backup avisa antes que el healthcheck" "no se pudieron leer los umbrales"
  elif [ "$alerta" -le "$maxage" ]; then
    ok "la alerta de backup ($((alerta/3600)) h) avisa antes que el healthcheck ($((maxage/3600)) h)"
  else
    bad "la alerta de backup avisa antes que el healthcheck" \
        "alerta $((alerta/3600)) h > healthcheck $((maxage/3600)) h — el contenedor se pone rojo primero"
  fi

  # --- Binds ---
  # Su API es interna: la scrapea Prometheus por nombre, nadie desde el host.

  sin_publicar alloy 12345
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_alloy
resumen
