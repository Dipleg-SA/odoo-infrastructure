# Operar backups

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar el contenedor `backup` (restic) sin tocar el resto del stack. **No es donde corrés un backup** — eso es [realizar-backup](../backup-restore/realizar-backup.md). Este runbook es solo el ciclo de vida del contenedor.

Exclusiva de producción: `require-backups` en el Makefile falla si el stack no incluye esta capa — staging y development no la llevan.

## Objetivo

El contenedor `backup` en el estado pedido. **pgBackRest no tiene contenedor propio** — vive dentro de la imagen de Postgres, porque su `archive_command` lo ejecuta el proceso de la base. Operar esta capa nunca sube ni baja pgBackRest: eso corre junto con `postgres` (ver [operar-db](operar-db.md)).

## Comandos

```bash
make backups-up
make backups-down
make backups-restart   # docker compose restart — no recrea el contenedor
make backups-logs
make backups-ps
make backups-verify
```

**Bajar esta capa no detiene el archivado de WAL** — eso sigue corriendo mientras `postgres` esté arriba, porque vive ahí. Lo que se detiene es el contenedor `backup` (restic) y, con él, la posibilidad de correr `make backup`/`backup-full` hasta que vuelva a subir.

## Verificación

```bash
make backups-verify
```

Cubre el snapshot de restic, el full de pgBackRest, el registro de addons, los dos timers de systemd activos con el nombre de este stack, el `OnFailure=` cableado, y que ningún contenedor del perfil `restore` esté corriendo.

Si el contenedor sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora. **No lo recrees para forzarlo** — le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención.

---

**Destructivo — `make backups-nuke`.** Borra containers e imágenes de esta capa; **`docker/backups/backup/compose.yaml` no declara ningún volumen**, así que el comando anuncia `volúmenes (ninguno)` y no hay estado en disco que perder acá. Pide tipear `nuke`. No toca el repositorio remoto en R2 —eso vive fuera de Docker— ni el de pgBackRest, que al vivir dentro de `postgres` cae bajo [operar-db](operar-db.md).

Si `restore-files` está levantado, el nuke termina con `⚠ alguna imagen quedó sin borrar`: comparte la imagen de `restic` con `backup`, y Docker no la borra mientras un contenedor la use. Es benigno — el comando cierra con `✓` y exit `0`.
