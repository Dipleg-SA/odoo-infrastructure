# nginx no arranca: cannot load certificate

## Síntoma

nginx se niega a levantar, con un error de certificado en el log.

## Diagnóstico

Es el orden invertido, no una falla. nginx no arranca si el archivo del certificado no existe, y quien lo emite es certbot.

```bash
docker compose logs --tail=20 nginx
```

## Fix

En un deploy nuevo, el certificado va **antes** del primer `up`:

```bash
make cert-issue
```

Con DNS-01 no hace falta que nginx esté vivo para emitir: la validación va contra la API de Cloudflare, no contra el puerto 80. Ver [levantar-produccion](../../entorno/levantar-produccion.md) fase 3.
