# 502 Bad Gateway de Cloudflare con todos los servicios healthy

## Síntoma

El stack interno anda —todo `healthy`— pero Cloudflare devuelve 502 en el hostname público.

## Diagnóstico

Lo que falla es la identidad TLS del origen. El log de `cloudflared` dice qué nombre esperaba:

```bash
docker compose logs --tail=20 cloudflared | grep -o 'error="[^"]*"' | sort -u
```

Para aislar en qué eslabón está el problema, un contenedor descartable en la red `edge` (`cloudflared` es distroless, no tiene shell propia):

```bash
docker run --rm --network "$(docker compose config | awk '/^name:/{print $2}')_edge" curlimages/curl -sk -o /dev/null -w "%{http_code}\n" https://nginx:443 -H "Host: $PUBLIC_HOSTNAME"
```

Si eso da `303`/`200`, nginx y Odoo están bien y el problema es exclusivamente TLS entre `cloudflared` y nginx.

## Fix

- **`x509: certificate is valid for <tu PUBLIC_HOSTNAME>, not nginx`** → el **Origin Server Name está vacío** en el Public Hostname del Tunnel. `cloudflared` valida el certificado contra el nombre del servicio (`nginx`), que no es el del certificado. Se arregla **solo en el dashboard** (Zero Trust → Networks → Tunnels → el Tunnel → Public Hostname → Additional application settings → TLS → Origin Server Name = `$PUBLIC_HOSTNAME`). `cloudflared` recarga solo, sin restart: confirmalo con `docker compose logs --tail=5 cloudflared | grep "Updated to new configuration"`, que debe mostrar `"originServerName":"<tu PUBLIC_HOSTNAME>"`.
- **`x509: certificate signed by unknown authority`** → el certificado salió del entorno de staging de Let's Encrypt, que no es confiable para `cloudflared`. Revisá que `make cert-issue` no lleve `--staging` y reemití.
