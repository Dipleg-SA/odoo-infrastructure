# unable to restore while PostgreSQL is running, con Postgres ya detenido

## Síntoma

`pgbackrest restore` rechaza la corrida diciendo que Postgres está corriendo, aunque el contenedor ya esté parado.

## Diagnóstico

Quedó un `postmaster.pid` de un apagado sucio. La imagen usa `STOPSIGNAL SIGINT` (fast shutdown), pero con Odoo y PgBouncer conectados no alcanza a cerrar en los 10s por defecto y Docker lo mata.

## Fix

Parar con timeout la próxima vez:

```bash
docker compose stop -t 60 postgres
```

Y confirmar que el `postmaster.pid` no está antes de reintentar el restore.
