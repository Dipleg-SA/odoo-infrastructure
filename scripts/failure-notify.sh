#!/usr/bin/env bash
# Aviso de unit fallida. Lo invoca el OnFailure= de las units de backup y
# de renovación de certificado; recibe el nombre de la que falló. Reusa la
# credencial SMTP de la capa correspondiente, sin introducir ninguna nueva.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

UNIT="${1:-desconocida}"

# --- Config ---
# El remitente/destinatario varían por deployment; la credencial es un secret.

set -a; . ./.env; set +a
: "${ALERT_EMAIL_FROM:?falta en .env — sin remitente no hay aviso de fallo}"
: "${ALERT_EMAIL_TO:?falta en .env — sin destinatario no hay aviso de fallo}"
: "${SMTP_USER:?falta en .env — sin usuario SMTP no hay aviso de fallo}"
: "${SMTP_HOST:?falta en .env — sin host SMTP no hay aviso de fallo}"
SMTP_PASS="$(cat secrets/zeptomail_smtp_password)"

ui_plan_start "failure-notify: $UNIT"
ui_step 1 "Envío del aviso de fallo por SMTP a $ALERT_EMAIL_TO."

# --- Envío ---
# STARTTLS en 587 (--ssl-reqd lo exige, no lo deja degradar a texto plano).

printf 'From: %s\nTo: %s\nSubject: [odoo] fallo en %s\n\nLa unit %s termino con error en %s a las %s.\nRevisar con: journalctl -u %s -n 50\n' \
  "$ALERT_EMAIL_FROM" "$ALERT_EMAIL_TO" "$UNIT" "$UNIT" "$(hostname)" "$(date -Is)" "$UNIT" \
| curl -sS --ssl-reqd \
    --url "smtp://${SMTP_HOST}:${SMTP_PORT:-587}" \
    --user "$SMTP_USER:$SMTP_PASS" \
    --mail-from "$ALERT_EMAIL_FROM" \
    --mail-rcpt "$ALERT_EMAIL_TO" \
    --upload-file -

echo
ui_step 2 "Finalizado."
ui_ok "failure-notify listo — aviso enviado a $ALERT_EMAIL_TO"
echo
