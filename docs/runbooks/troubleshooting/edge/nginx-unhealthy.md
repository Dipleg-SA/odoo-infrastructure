# nginx unhealthy

## Síntoma

`docker compose ps` marca `nginx` como `unhealthy`.

## Diagnóstico

Su healthcheck es `nginx -t`, así que un `unhealthy` es siempre config inválida:

```bash
docker compose logs --tail=20 nginx
```

La causa más común en un deploy nuevo es que `server-tls.conf` se bootstrapeó desde `server-tls.conf.example` y quedó el placeholder sin reemplazar:

```bash
docker compose exec nginx grep -r 'TU_DOMINIO' /etc/nginx/conf.d/
```

## Fix

Cualquier resultado en el grep es el placeholder `TU_DOMINIO` de `server-tls.conf.example` sin reemplazar en el `server-tls.conf` real de este checkout. Lo chequea también `make edge-verify`.
