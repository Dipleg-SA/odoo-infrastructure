#!/usr/bin/env bash
# Qué se espera del stack grafana. Dueño único de estos valores: el runbook
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

  # --- SMTP y destinatario realmente cargados ---
  # grafana.ini y contact-points.yaml ya no tienen placeholder: host/user/
  # from_address/destinatario llegan por env desde .env. Si alguna clave quedó
  # vacía ahí, acá se nota en el propio contenedor — GF_SMTP_HOST resuelve a
  # ":587" y no a un host real, por ejemplo — en vez de que Grafana arranque
  # igual y mande correo a una dirección que no existe, o no mande nada.

  if corriendo grafana; then
    vacio "SMTP y destinatario de alertas sin claves vacías en .env" \
      docker compose exec -T grafana sh -c \
        '[ -n "$GF_SMTP_USER" ] && [ "$GF_SMTP_HOST" != ":587" ] && [ -n "$GF_SMTP_FROM_ADDRESS" ] && [ -n "$ALERT_EMAIL_TO" ] || echo "alguna quedo vacia"'
  else
    omitir "SMTP y destinatario de alertas sin claves vacías en .env" "$(motivo grafana)"
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
