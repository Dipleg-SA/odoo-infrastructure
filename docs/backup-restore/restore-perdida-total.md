# Restore de pérdida total

## Cuándo se usa

El servidor de producción no existe más, o sus datos son irrecuperables. Para sembrar
staging o correr el simulacro semestral, usá [restore-staging](restore-staging.md):
ese entorno tiene otros nombres de proyecto y credenciales de solo lectura.

## Objetivo

Recuperar la base y el filestore desde el último snapshot, sobre un checkout que puede
no ser el que lo escribió.

## Flujo rápido

Este procedimiento es para recuperar producción. Para sembrar staging, seguí
[restore-staging](restore-staging.md).

1. **Reconstruir el checkout de producción.** Recuperar el nombre de proyecto original, configs,
   secrets y addons; ver [A mano](#a-mano).
2. **Restaurar las dos partes del estado.** Consultar el inventario de addons si hace falta,
   iniciar Postgres y restaurar filestore y base desde el mismo snapshot; ver [Comandos](#comandos).
3. **Reponer código y levantar servicios.** Sincronizar addons, resolver dependencias, reemitir el
   certificado, preparar el monitoreo y arrancar el stack antes de reactivar backups y timers; ver
   [Comandos](#comandos).
4. **Confirmar la recuperación.** Ejecutar las verificaciones y descargar un adjunto desde la
   aplicación; ver [Verificación](#verificación).

## A mano

Antes de empezar, el checkout tiene que estar bootstrapeado: `.env` con su
`COMPOSE_PROJECT_NAME`, los configs reales copiados de sus `.example`, y los secrets
cargados —incluidos `restic_password` y `restic_r2_credentials`, que tienen que ser
**los del repositorio de origen**, o no hay nada que leer.

`RESTIC_REPOSITORY` en `stacks/backup/config/r2.env` apunta al repositorio de origen,
letra por letra. En la recuperación de producción, conserva el `COMPOSE_PROJECT_NAME`
original: restic agrupa los snapshots por ese nombre y `backup-verify` lo usa para
encontrar los de este stack.

El snapshot guarda la base, el filestore y un inventario informativo de ramas y commits
de addons en `state/meta/addons.txt`; no guarda los repositorios ni el manifiesto
`addons/addons.txt`. Recuperá el manifiesto y el ZIP de Enterprise, si se usa, desde su
copia externa. Los commits de addons que registra el inventario tienen que seguir
disponibles en sus repositorios remotos. Odoo aborta si levantás sin addons.

Si se perdió el servidor entero, primero reconstruí Docker y los prerrequisitos del
host con [configurar-docker-host](../operacion/configurar-docker-host.md). En el
checkout nuevo, seguí [levantar-produccion](../entorno/levantar-produccion.md) hasta
completar el bootstrap, incluido `sudo make host-init`, y recuperar `.env`, secrets,
configs, el manifiesto de addons y las imágenes. Detenete antes de levantar Odoo.

## Comandos

Completá `addons/addons.txt` antes de sincronizar. Si no tenés la copia externa, podés
consultar el inventario que guarda el snapshot. Si vas a restaurar uno concreto, poné
el mismo ID en `SNAPSHOT` para ambos comandos:

```bash
SNAPSHOT=latest   # o el ID del snapshot elegido
docker compose run --rm --entrypoint restic -T backup dump "$SNAPSHOT" /data/meta/addons.txt
```

```bash
make postgres-up                 # el motor tiene que estar arriba: el dump entra por psql
make restore SNAPSHOT="$SNAPSHOT"
make repo-sync                   # primero completar addons/addons.txt
make addons-deps
make build                       # solo si addons-deps agregó o cambió pines
make cert-issue                  # el volumen de certificados no está en el backup
make monitoring-role             # el dump lógico no restaura roles de Postgres
sudo make up-timers
make up                          # levanta Edge, backup y observabilidad también
make backup-run                  # crea un snapshot nuevo de la instancia recuperada
```

**El orden interno no es simétrico al del backup, y es deliberado:** primero el
filestore, después la base. Un filestore más nuevo que la base deja archivos huérfanos,
que son inofensivos; uno más viejo deja filas de `ir_attachment` apuntando a archivos
que no existen, que es destructivo y silencioso.

`restore` se niega a correr con Odoo levantado: las conexiones vivas bloquean el `DROP`
y lo que sí entra queda mezclado.

**El restore corre como root** y le devuelve al filestore el owner `100:101` que Odoo
necesita. Eso se eleva en la invocación, no en el compose, para que la operación
recurrente —el backup diario— siga corriendo sin privilegios.

## Verificación

```bash
make verify
```

Y lo que ninguna verificación automática cubre: **abrir la aplicación y comprobar que un
adjunto se descarga**. Es lo único que prueba que las dos mitades corresponden entre sí.
