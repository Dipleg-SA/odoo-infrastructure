# cloudflared no conecta

## Síntoma

`cloudflared` no establece la conexión del Tunnel.

## Diagnóstico

```bash
docker compose logs --tail=20 cloudflared
```

## Fix

El token del Tunnel en `secrets/cloudflare_tunnel_token` está mal copiado o expiró, o hay egress bloqueado hacia Cloudflare desde el servidor. Si es el token, ver [rotar-token-cloudflare-tunnel](../../credenciales/rotar-token-cloudflare-tunnel.md).
