# Operar db

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar `postgres` sin tocar el resto del stack — por ejemplo, para aplicar un cambio en `stacks/postgres/config/postgresql.conf`.

## Objetivo

La capa de datos en el estado pedido. A diferencia de las demás capas, esta es una dependencia dura de Odoo: bajarla o reiniciarla sin coordinar rompe la aplicación mientras dure.

## Comandos

```bash
make postgres-up
make postgres-down
make postgres-restart      # docker compose restart — no recrea contenedores
make postgres-logs
make postgres-ps
make postgres-verify
```

**Nunca `postgres-down`/`postgres-restart` con Odoo arriba, sin avisar.** Odoo queda con conexiones abiertas; si necesitás bajar Postgres de forma limpia, pará primero los servicios que dependen de él y usá un timeout explícito:

```bash
docker compose stop odoo
docker compose stop -t 60 postgres
```

El `-t 60` no es cosmético: con Odoo conectado, Postgres no cierra en los 10s por defecto que usa un `stop` simple, Docker lo mata, y el `postmaster.pid` que queda bloquea cualquier arranque posterior hasta que se limpie a mano.

## Verificación

```bash
make postgres-verify
```

Cubre el servicio `healthy`, que acepte conexiones, los logs sin errores de permisos, que el puerto no esté publicado, y que las conexiones que Odoo puede abrir —`db_maxconn` por sus procesos— entren en `max_connections`: sin pooler, pasarse no encola, Postgres rechaza.

---

**Destructivo — sin target, a mano.** Tampoco sobrevivió un nuke acotado a esta capa: el único que queda es `make nuke`, **global** — se lleva `pgdata` junto con los volúmenes de todos los demás stacks, `addons/` y `state/` enteros. Pide tipear `nuke`, sin imprimir ningún nombre de volumen antes: la palabra es la única confirmación que hay.

En producción o staging esto es indistinguible de perder la base —y todo lo demás—: antes de correrlo, confirmá que hay un backup reciente y probado (ver [realizar-backup](../backup-restore/realizar-backup.md)). Para borrar solo `pgdata`:

```bash
docker compose rm -sf postgres
docker volume rm "${COMPOSE_PROJECT_NAME}_pgdata"
```

