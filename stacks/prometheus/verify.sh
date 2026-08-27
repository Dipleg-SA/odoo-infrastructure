#!/usr/bin/env bash
# Qué se espera del stack prometheus. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_prometheus() {
  titulo "prometheus"

  sano prometheus

  # --- Todos los targets arriba ---
  # Es la señal de que el pull funciona. Alloy figura entre ellos a propósito:
  # si el agente se muere, su propia caída dispara up == 0 en vez de dejar las
  # series ausentes, que ningún umbral alcanza.

  local salida caidos
  if ! corriendo prometheus; then
    omitir "todos los targets de Prometheus up" "$(motivo prometheus)"
  elif ! salida=$(docker compose exec -T prometheus wget -qO- \
       'http://127.0.0.1:9090/api/v1/targets?state=active' 2>/dev/null); then
    bad "todos los targets de Prometheus up" "no se pudo consultar la API de targets"
  else
    # scrapePool y no job: job vive DENTRO de labels, un objeto anidado — [^{}]*
    # cruzaría su cierre y se comería el health de otro target. scrapePool está al
    # mismo nivel que health, sin llaves de por medio.
    caidos=$(printf '%s' "$salida" \
      | grep -oE '"scrapePool": ?"[^"]*"[^{}]*"health": ?"down"' \
      | sed -E 's/"scrapePool": ?"([^"]*)".*/\1/' | sort -u | tr '\n' ' ')
    if [ -z "$caidos" ]; then ok "todos los targets de Prometheus up"
    else bad "todos los targets de Prometheus up" "caídos: ${caidos% } — docker compose logs <ese-servicio>"; fi
  fi

  # --- Las tres familias que empuja Alloy ---
  # Host, contenedores y base: si falta una, el agente perdió un colector. Se
  # verifica acá y no en alloy porque lo que importa es que HAYAN LLEGADO, no que
  # el colector diga estar sano.

  local m
  if ! corriendo prometheus; then
    omitir "las tres familias de métricas presentes" "$(motivo prometheus)"
  else
    for m in node_memory_MemAvailable_bytes container_memory_usage_bytes pg_up; do
      if docker compose exec -T prometheus wget -qO- \
           "http://127.0.0.1:9090/api/v1/query?query=count($m)" 2>/dev/null | grep -q '"value"'; then
        ok "métrica $m presente"
      else
        bad "métrica $m presente" "sin series — Alloy no está empujando esa familia"
      fi
    done
  fi

  # --- Binds ---
  # Nivel 1: solo por nombre dentro de su red. Se consulta desde Grafana.

  sin_publicar prometheus 9090
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_prometheus
resumen
