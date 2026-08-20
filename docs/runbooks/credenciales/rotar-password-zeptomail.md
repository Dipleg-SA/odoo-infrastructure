# Rotar credencial de ZeptoMail

## Cuándo se usa

La credencial SMTP de `secrets/zeptomail_smtp_password` venció, se filtró, o toca rotarla por política. Tiene **tres consumidores distintos**, cada uno fallando por su lado si algo queda mal: Odoo (mail de la aplicación), `scripts/failure-notify.sh` (aviso de backup fallido, vía systemd), y Grafana (contact point de alertas).

## Objetivo

Los tres consumidores usando la credencial nueva, verificado uno por uno — no alcanza con confirmar que el archivo cambió.

## A mano

Generar el token nuevo en ZeptoMail → Mail Agents → el agente → SMTP & API. Confirmar el `Username` literal (`SMTP_USER` en `.env`, no cambia con la rotación salvo que también lo hayas modificado).

## Comandos

```bash
echo "# 1 → Reemplazar el archivo"
sudo -e secrets/zeptomail_smtp_password
sudo make secrets-perms
```

**Odoo y Grafana necesitan recrearse** — el secret es un bind-mount de archivo atado al inode, y Odoo además solo lee el valor una vez, al armar `odoo.conf` en el entrypoint:

```bash
docker compose up -d --force-recreate odoo grafana
```

`scripts/failure-notify.sh` no necesita nada: lee el archivo directo en cada invocación, disparada por la unit de systemd.

## Verificación

Primero la credencial sola, después los tres consumidores — en el mismo orden que se prueban la primera vez:

```bash
echo "# 1 → Directo, sin pasar por ningún contenedor"
ZM_USER='emailapikey'  # el que corresponda — el mismo que SMTP_USER en .env
ZM_TOKEN=$(sudo cat secrets/zeptomail_smtp_password)   # sudo: los secrets son 640 con grupo del consumidor
printf 'From: %s\nTo: %s\nSubject: prueba rotación\n\nok\n' "$ALERT_EMAIL_FROM" "$ALERT_EMAIL_TO" \
  | curl -sS --ssl-reqd --url smtp://smtp.zeptomail.com:587 \
      --user "$ZM_USER:$ZM_TOKEN" --mail-from "$ALERT_EMAIL_FROM" --mail-rcpt "$ALERT_EMAIL_TO" --upload-file -
```

```bash
echo "# 2 → La unit real de systemd"
sudo systemctl start odoo-notify@prueba.service
systemctl show -p Result --value odoo-notify@prueba.service   # tiene que dar Result=success
```

```bash
echo "# 3 → Grafana"
```
Alertas → Contact points → `email-operador` → **Test**, en la UI (túnel SSH, ver [operar-observability](../operacion/operar-observability.md)).

```bash
echo "# 4 → Odoo mismo"
```
Disparar una notificación saliente desde la aplicación (invitar un usuario alcanza) y confirmar que llega.

Los cuatro pasos tienen que dar bien. Un rechazo puntual casi siempre es saldo de créditos o remitente sin verificar — lo mismo que se prueba la primera vez, no un problema de la rotación en sí.
