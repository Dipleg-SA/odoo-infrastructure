# postgres/pgbouncer unhealthy

## Síntoma

`docker compose ps` marca `postgres` o `pgbouncer` como `unhealthy`.

## Diagnóstico

```bash
docker compose logs --tail=30 postgres pgbouncer
```

## Fix

Causas típicas:

- Permisos incorrectos en `pgbouncer_credentials` — si estás probando en Mac en vez del servidor real, Docker Desktop no respeta fielmente los permisos POSIX en bind-mounts owned-por-root (limitación de su capa de virtualización, no un bug de este repo; verificado que el mismo mecanismo funciona bien en el servidor Linux real).
- El archivo no tiene el formato exacto `"odoo" "password"` (comillas incluidas).
- El puerto ya está ocupado por otra instancia de Postgres en el host.
