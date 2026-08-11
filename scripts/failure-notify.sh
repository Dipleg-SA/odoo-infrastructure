#!/usr/bin/env bash
# Aviso de corrida de backup fallida. Lo invoca el OnFailure= de las
# units; recibe el nombre de la unit que falló. Reusa la credencial SMTP de
# ZeptoMail de la capa correspondiente, sin introducir ninguna credencial nueva.
set -euo pipefail

cd "$(dirname "$0")/.."

UNIT="${1:-desconocida}"

# --- Config ---
# El remitente/destinatario varían por deployment; la credencial es un secret.

set -a; . ./.env; set +a
: "${ALERT_EMAIL_FROM:?falta en .env — sin remitente no hay aviso de backup fallido}"
: "${ALERT_EMAIL_TO:?falta en .env — sin destinatario no hay aviso de backup fallido}"
: "${SMTP_USER:?falta en .env — sin usuario SMTP no hay aviso de backup fallido}"
SMTP_PASS="$(cat secrets/zeptomail_smtp_password)"

# --- Envío ---
# STARTTLS en 587 (--ssl-reqd lo exige, no lo deja degradar a texto plano).

printf 'From: %s\nTo: %s\nSubject: [odoo-backup] fallo en %s\n\nLa unit %s termino con error en %s a las %s.\nRevisar con: journalctl -u %s -n 50\n' \
  "$ALERT_EMAIL_FROM" "$ALERT_EMAIL_TO" "$UNIT" "$UNIT" "$(hostname)" "$(date -Is)" "$UNIT" \
| curl -sS --ssl-reqd \
    --url "smtp://smtp.zeptomail.com:587" \
    --user "$SMTP_USER:$SMTP_PASS" \
    --mail-from "$ALERT_EMAIL_FROM" \
    --mail-rcpt "$ALERT_EMAIL_TO" \
    --upload-file -
