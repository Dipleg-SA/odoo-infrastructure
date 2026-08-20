# nginx unhealthy

## Síntoma

`docker compose ps` marca `nginx` como `unhealthy`.

## Diagnóstico

Su healthcheck es `nginx -t`, así que un `unhealthy` es siempre config inválida:

```bash
docker compose logs --tail=20 nginx
```

La causa más común en un deploy nuevo es que la sustitución de variables no corrió y quedó el literal `${PUBLIC_HOSTNAME}` dentro de la config:

```bash
docker compose exec nginx grep -r '\${' /etc/nginx/conf.d/
```

## Fix

Cualquier resultado en el grep es un `envsubst` que no sustituyó: revisá que la variable esté en `.env` y que `NGINX_ENVSUBST_FILTER` en `docker/compose.proxy.yaml` la cubra. Lo chequea también `make edge-verify`.
