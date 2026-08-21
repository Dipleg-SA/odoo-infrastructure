# Configurar ZeptoMail

## Cuándo se usa

Antes de clonar el repositorio. La verificación del dominio de envío escribe SPF/DKIM en el DNS, así que depende de que [la zona de Cloudflare](crear-zona-cloudflare.md) ya esté delegada y propagada.

## Objetivo

Dominio de envío verificado, un Mail Agent con credencial SMTP, y saldo cargado — sin créditos la alerta se detecta pero no sale.

## A mano

1. Cuenta en ZeptoMail, dominio de envío verificado (SPF/DKIM contra tu zona de Cloudflare).
2. Mail Agents → crear uno → SMTP & API: ahí está el `Username` literal (`SMTP_USER` en `.env`, casi siempre `emailapikey`, **no es tu dirección de correo**) y el token.
3. Cargar saldo — sin créditos, ZeptoMail rechaza el envío en silencio para el resto de este stack, no solo para esta prueba.

## Comandos

```bash
echo "# 1 → Completá estos tres antes de seguir"
ZM_USER='emailapikey'; ZM_FROM='remitente-verificado@tu-dominio'; ZM_TO='donde-querés-recibir@ejemplo'
```

```bash
echo "# 2 → Token del Mail Agent (pegalo y Enter, no se muestra)"
read -rs ZM_TOKEN && printf 'From: %s\nTo: %s\nSubject: prueba\n\nok\n' "$ZM_FROM" "$ZM_TO" \
  | curl -sS --ssl-reqd --url smtp://smtp.zeptomail.com:587 \
      --user "$ZM_USER:$ZM_TOKEN" --mail-from "$ZM_FROM" --mail-rcpt "$ZM_TO" --upload-file - \
  && echo "OK: aceptado por ZeptoMail — confirmá que llegó a $ZM_TO"
```

El token va **sin el prefijo `Zoho-enczapikey`**, que es para el header HTTP de la API, no para SMTP. El `read` va en el último comando y lo que usa el valor cuelga del mismo `&&`: si quedara una línea suelta debajo, `read` se la comería como valor y el `curl` no correría — sin error y sin salida.

## Verificación

El bloque 2 ya es la prueba: `OK` impreso **y** el mail efectivamente recibido en `$ZM_TO` — lo primero confirma que ZeptoMail lo aceptó, no que llegó.

Guardá `ZM_USER` (→ `SMTP_USER`), el remitente (→ `ALERT_EMAIL_FROM`) y el token (→ `secrets/zeptomail_smtp_password`). Ese mismo usuario lo usa después `scripts/failure-notify.sh` para el aviso de backup fallido — acertarlo acá evita que falle en silencio más adelante.

---

Para rotar la credencial más adelante, con los tres consumidores (Odoo, `failure-notify.sh`, Grafana): [rotar-password-zeptomail](../credenciales/rotar-password-zeptomail.md).
