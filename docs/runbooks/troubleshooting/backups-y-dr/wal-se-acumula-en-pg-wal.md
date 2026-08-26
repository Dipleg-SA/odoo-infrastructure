# El WAL se acumula en pg_wal

## Síntoma

Archivos `.ready` que crecen en `pg_wal`. El archivado está roto y el disco de la base se va a llenar.

## Diagnóstico

```bash
docker compose exec -u postgres postgres pgbackrest check
```

Los backups full/diff pueden seguir aparentando éxito mientras esto pasa — por eso `check` corre primero en cada corrida diaria (ver [realizar-backup](../../backup-restore/realizar-backup.md)).

## Fix

Causas típicas: credencial de R2 vencida o mal rotada (ver [rotar-credenciales-r2](../../credenciales/rotar-credenciales-r2.md)), `docker/db/postgres/pgbackrest.conf` sin sección de stanza, o el bucket inalcanzable.
