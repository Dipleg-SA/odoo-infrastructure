#!/usr/bin/env bash
# Qué se espera del stack grafana. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

RULES=stacks/grafana/config/provisioning/alerting/rules.yaml

v_grafana() {
  titulo "grafana"

  sano grafana

  # --- Reglas de alerting realmente cargadas ---
  # Se cuentan contra el archivo, no se asume que cargó. Un fallo de provisioning
  # completo NO es silencioso —Grafana sale con código 1 y entra en loop, y eso lo
  # atrapa `sano grafana`—, pero una regla que no provisiona sí lo es: el resto
  # carga, el stack se ve sano, y esa alerta no dispara nunca.

  local esperadas cargadas codigo pass_gf
  esperadas=$(grep -c '^      - uid:' "$RULES" 2>/dev/null)
  if [ "${esperadas:-0}" -eq 0 ]; then
    bad "reglas de alerting cargadas" \
        "no se pudo contar ninguna en rules.yaml — el chequeo no verifica nada hasta arreglar el conteo"
  elif ! corriendo grafana; then
    omitir "las $esperadas reglas de alerting cargadas" "$(motivo grafana)"
  # El secret es 640 root:472 y el operador no está en ese grupo: desde el host es
  # ilegible siempre. Adentro sí, que corre 472:0 con el 472 como suplementario.
  elif ! pass_gf=$(docker compose exec -T grafana cat /run/secrets/grafana_admin_password 2>/dev/null | tr -d '\r\n') || [ -z "$pass_gf" ]; then
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

  # --- Placeholders sin reemplazar ---
  # Ninguno de los dos interpola desde .env: si quedó el placeholder de su
  # .example, Grafana arranca igual y manda correo a una dirección que no existe,
  # o no manda nada, sin avisar.

  sin_placeholder "grafana.ini sin el placeholder de su .example" \
    stacks/grafana/config/grafana.ini 'TU_SMTP_HOST|TU_EMAIL_ALERTA_FROM'
  sin_placeholder "contact-points.yaml sin el placeholder de su .example" \
    stacks/grafana/config/provisioning/alerting/contact-points.yaml 'TU_EMAIL_ALERTA_TO'

  # --- Binds ---
  # Nivel 2: única UI administrativa del stack, en loopback. Se entra por túnel SSH.

  bind_es grafana 3000
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_grafana
resumen
