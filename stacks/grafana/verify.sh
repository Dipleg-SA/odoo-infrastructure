#!/usr/bin/env bash
# Qué se espera del stack grafana. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

RULES=stacks/grafana/config/provisioning/alerting/rules.yaml

v_grafana() {
  titulo "grafana"

  sano grafana

  # --- Reglas de alerting realmente cargadas ---
  # Se cuentan en la API de Grafana porque una regla ausente no siempre tumba el stack.

  local esperadas cargadas codigo pass_gf
  esperadas=$(grep -c '^      - uid:' "$RULES" 2>/dev/null)
  if [ "${esperadas:-0}" -eq 0 ]; then
    bad "reglas de alerting cargadas" \
        "no se pudo contar ninguna en rules.yaml — el chequeo no verifica nada hasta arreglar el conteo"
  elif ! corriendo grafana; then
    omitir "las $esperadas reglas de alerting cargadas" "$(motivo grafana)"
  # El secret es 640 root:472 y el operador no está en ese grupo: desde el host es
  # ilegible siempre. Adentro sí, que corre 472:0 con el 472 como suplementario.
  elif ! pass_gf=$(contexto_compose exec -T grafana cat /run/secrets/grafana_admin_password 2>/dev/null | tr -d '\r\n') || [ -z "$pass_gf" ]; then
    omitir "las $esperadas reglas de alerting cargadas" "no se pudo leer el secret desde el contenedor"
  else
    codigo=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -u "admin:$pass_gf" \
      http://127.0.0.1:3001/api/v1/provisioning/alert-rules 2>/dev/null)
    if [ "$codigo" != "200" ]; then
      omitir "las $esperadas reglas de alerting cargadas" "la API respondió $codigo, no 200"
    else
      cargadas=$(curl -s -m 10 -u "admin:$pass_gf" \
        http://127.0.0.1:3001/api/v1/provisioning/alert-rules 2>/dev/null \
        | grep -o '"uid":' | wc -l | tr -d ' ')
      if [ "${cargadas:-0}" -ge "$esperadas" ]; then
        ok "las $esperadas reglas de alerting cargadas"
      else
        bad "las $esperadas reglas de alerting cargadas" \
            "solo ${cargadas:-0} — hay reglas que no provisionaron y no van a disparar nunca"
      fi
    fi
  fi

  # --- SMTP y destinatario realmente cargados ---
  # La consulta dentro del contenedor confirma que host, usuario y destinatario tienen valor.

  if corriendo grafana; then
    vacio "SMTP y destinatario de alertas sin claves vacías en runtime/$ENTORNO/compose.env" \
      contexto_compose exec -T grafana sh -c \
        '[ -n "$GF_SMTP_USER" ] && [ "$GF_SMTP_HOST" != ":587" ] && [ -n "$GF_SMTP_FROM_ADDRESS" ] && [ -n "$ALERT_EMAIL_TO" ] || echo "alguna quedo vacia"'
  else
    omitir "SMTP y destinatario de alertas sin claves vacías en runtime/$ENTORNO/compose.env" "$(motivo grafana)"
  fi

  # --- Binds ---
  # Nivel 2: única UI administrativa del stack, en loopback. Se entra por túnel SSH.

  bind_es grafana 3000
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_grafana
resumen
