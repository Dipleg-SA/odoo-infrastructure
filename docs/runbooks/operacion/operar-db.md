# Operar db

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar `postgres` + `pgbouncer` sin tocar el resto del stack — por ejemplo, para aplicar un cambio en `config/postgres/postgresql.conf`, o antes de un restore (ver [restore-pitr](../backup-restore/restore-pitr.md), que apaga esta capa con un timeout explícito antes de tocarla).

## Objetivo

La capa de datos en el estado pedido. A diferencia de las demás capas, esta es una dependencia dura de Odoo: bajarla o reiniciarla sin coordinar rompe la aplicación mientras dure.

## Comandos

```bash
make db-up
make db-down
make db-restart      # docker compose restart — no recrea contenedores
make db-logs
make db-ps
make db-verify
```

**Nunca `db-down`/`db-restart` con Odoo arriba, sin avisar.** Odoo y PgBouncer quedan con conexiones abiertas; si necesitás bajar Postgres de forma limpia (por ejemplo antes de un restore), pará primero los servicios que dependen de él y usá un timeout explícito:

```bash
docker compose stop odoo
docker compose stop -t 60 postgres
```

El `-t 60` no es cosmético: con Odoo y PgBouncer conectados, Postgres no cierra en los 10s por defecto que usa un `stop` simple, Docker lo mata, y el `postmaster.pid` que queda bloquea cualquier restore posterior hasta que se limpie a mano.

## Verificación

```bash
make db-verify
```

Cubre los dos servicios `healthy`, `archive_mode` y `archive_command` según lo que este stack espera (`PG_ARCHIVE_MODE`), la stanza cifrada en R2, que no haya WAL pendiente de archivar, los logs sin errores de permisos, que ningún puerto esté publicado, y la autenticación real **a través de PgBouncer** — no alcanza con que el puerto responda.

---

**Destructivo — `make db-nuke`.** Borra containers, imágenes **y el volumen `pgdata`** de esta capa. Pide tipear `nuke`.

En producción o staging esto es indistinguible de perder la base: antes de correrlo, confirmá que hay un backup reciente y probado (ver [realizar-backup](../backup-restore/realizar-backup.md)). El comando imprime el nombre real del volumen —el que Docker conoce, prefijado por proyecto (`<proyecto>_pgdata`)— **antes** de pedir la confirmación: si ahí ves un nombre que no esperabas, cancelá.

Si `restore-db` está levantado, el nuke termina con un aviso: `⚠ alguna imagen quedó sin borrar`. Es esperado y benigno — `restore-db` usa la misma imagen que `postgres`, y Docker no la borra mientras un contenedor la use. Los containers y el volumen sí se borraron; la imagen se rehace con `docker compose build postgres`. Por eso el comando igual cierra con `✓` y exit `0`.
