# El certificado no se renueva

## Síntoma

El certificado se acerca al vencimiento (o la alerta `cert-por-vencer` disparó) y no se renovó solo.

## Diagnóstico

La renovación no vive en ningún contenedor: la corre el timer `odoo-cert-renew.timer`, dos veces por día.

```bash
systemctl list-timers odoo-cert-renew.timer
journalctl -u odoo-cert-renew.service -n 30
```

Un fallo manda mail por el `OnFailure=`, igual que los backups.

Hay un caso que el timer **no** cubre y la alerta tampoco: que certbot renueve bien y nginx siga sirviendo el certificado viejo porque nadie lo recargó. La métrica `odoo_cert_expiry_timestamp_seconds` (que escribe `cert.sh` en `state/textfile/`, y de ahí levanta Alloy) mide lo que certbot tiene en disco, **no** lo que nginx está sirviendo.

## Fix

`scripts/cert.sh renew` hace el reload como parte de la corrida; si hace falta forzarlo:

```bash
docker compose exec nginx nginx -s reload
```

Let's Encrypt dejó de mandar avisos de vencimiento el 2025-06-04, así que la vigilancia es activa: la alerta `cert-por-vencer` dispara a los 21 días restantes, ~9 días después de que la renovación automática debió correr, y cubre también que la métrica no exista, porque sin serie la regla alerta igual.
