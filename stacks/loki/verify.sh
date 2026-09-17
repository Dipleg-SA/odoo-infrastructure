#!/usr/bin/env bash
# Qué se espera del stack loki. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_loki() {
  titulo "loki"

  if ! declarado loki; then
    omitir "loki levantado" "no está en este stack"
    return
  fi

  # --- Retención efectiva ---
  # La configuración montada es la única fuente; exige un período y el compactor activo.

  local archivo_retencion="$RUNTIME_CONFIG_DIR/loki/loki.yaml" retenciones
  retenciones=$(grep -cE '^[[:space:]]+retention_period:[[:space:]]+[^[:space:]]+$' "$archivo_retencion" 2>/dev/null || true)
  if [ "$retenciones" -eq 1 ] && grep -qE '^  retention_enabled:[[:space:]]+true$' "$archivo_retencion" 2>/dev/null; then
    ok "loki retención efectiva declarada y aplicada"
  else
    bad "loki retención efectiva declarada y aplicada" \
      "revisar $archivo_retencion: retention_period único y compactor.retention_enabled=true"
  fi

  if ! corriendo loki; then
    bad "loki levantado" "no está corriendo"
    omitir "Loki recibe logs por contenedor" "loki no está corriendo"
    omitir "loki:3100 sin publicar" "loki no está corriendo"
    return
  fi
  ok "loki up (sin healthcheck propio: imagen distroless)"

  # --- Logs de verdad, etiquetados por contenedor ---
  # Prometheus consulta Loki por la red interna porque el puerto no se publica.

  # Si Prometheus está caído, se omite el chequeo de recepción de logs.
  # Sin ese cliente no se puede concluir que Loki reciba eventos.
  if ! corriendo prometheus; then
    omitir "Loki recibe logs por contenedor" "$(motivo prometheus)"
  else
    expect "Loki recibe logs por contenedor" "odoo" contexto_compose exec -T prometheus \
      wget -qO- 'http://loki:3100/loki/api/v1/label/container/values'
  fi

  # --- Binds ---
  # Loki solo se consulta por la red de observabilidad.

  sin_publicar loki 3100
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_loki
resumen
