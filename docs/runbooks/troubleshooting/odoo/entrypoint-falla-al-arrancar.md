# El entrypoint falla al arrancar

## Síntoma

El contenedor `odoo` no arranca, o se cae apenas arriba.

## Diagnóstico

```bash
docker compose logs --tail=50 odoo
```

## Fix

Causas típicas:

- **GID incorrecto** en `odoo_admin_password`/`zeptomail_smtp_password` — deben ser `101`. Se arregla con `sudo make secrets-perms && make secrets-check` (el mapa vive en `scripts/secrets-perms.sh`, no acá).
- **Postgres/PgBouncer todavía no están `healthy`** cuando Odoo intenta conectar. Confirmar que `make db-verify` pasa antes de arrancar Odoo — ver [postgres-pgbouncer-unhealthy](../datos/postgres-pgbouncer-unhealthy.md) si no.
- **`addons_path` vacío** — el entrypoint aborta a propósito (`addons_path vacío — ¿corriste make addons-sync antes de levantar el stack?`). Desde el paso a bind-mount es la causa más frecuente: los addons llegan por bind-mount desde `addons/`, así que su presencia ya no la garantiza la imagen. Se arregla con `make addons-sync`; si eso falla por credencial, el token vive en `~/.git-credentials` del host — ver [rotar-token-git](../../credenciales/rotar-token-git.md).
