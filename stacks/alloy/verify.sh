#!/usr/bin/env bash
# Qué se espera del stack alloy. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

REGLAS=stacks/grafana/config/provisioning/alerting/rules.yaml
BACKUP_COMPOSE=stacks/backup/compose.yaml

v_alloy() {
  titulo "alloy"

  sano alloy

  # --- Los componentes resuelven de verdad ---
  # `alloy validate` acepta constantes inexistentes con exit 0: la ÚNICA prueba de
  # que las referencias entre componentes resuelven es ejecutarlo y leer su API.
  # Un componente en estado unhealthy deja de emitir y nada más lo dice.

  local comp rotos
  if ! corriendo alloy; then
    omitir "todos los componentes de Alloy sanos" "$(motivo alloy)"
  elif ! comp=$(docker compose exec -T alloy bash -c \
       'exec 3<>/dev/tcp/127.0.0.1/12345 && printf "GET /api/v0/web/components HTTP/1.0\r\n\r\n" >&3 && cat <&3' 2>/dev/null); then
    bad "todos los componentes de Alloy sanos" "no se pudo consultar la API de componentes"
  else
    # El estado va anidado en "health":{"state":...}, no en una clave "health_type"
    # de primer nivel — se midió contra la API real. Grepear la clave equivocada
    # daba cero coincidencias y el chequeo pasaba siempre, dijera lo que dijera Alloy.
    local total
    # wc -l y no grep -c: la API devuelve todo el JSON en UNA línea, así que
    # grep -c contaba líneas —siempre 1— en vez de componentes.
    total=$(printf '%s' "$comp" | grep -o '"health":{"state":"' | wc -l | tr -d ' ')
    rotos=$(printf '%s' "$comp" | grep -o '"health":{"state":"[a-z]*"' | grep -vc 'healthy' || true)
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
  # La alerta tiene que avisar ANTES de que el healthcheck marque unhealthy. Los dos
  # derivan de la cadencia del timer y viven en archivos de herramientas distintas.

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
