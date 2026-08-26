# unable to find primary cluster, en stanza-create

## Síntoma

`pgbackrest stanza-create` falla con `unable to find primary cluster`.

## Diagnóstico

pgBackRest se conecta a la base como rol `postgres`, que en este cluster no existe (se creó con `POSTGRES_USER=odoo`).

## Fix

El rol correcto llega por `PGBACKREST_PG1_USER` desde `docker/db/postgres/compose.yaml`; si el error aparece, es que esa variable no está en el entorno del contenedor. Revisar la config antes de reintentar.
