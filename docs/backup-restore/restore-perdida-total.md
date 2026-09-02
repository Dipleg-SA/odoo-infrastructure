# Restore de pérdida total

## Cuándo se usa

El servidor no existe más, o los datos son irrecuperables. También es el procedimiento
con el que se **siembra prueba** desde el snapshot de producción — son la misma
operación, y por eso el simulacro periódico no exige un ejercicio aparte.

## Objetivo

Recuperar la base y el filestore desde el último snapshot, sobre un checkout que puede
no ser el que lo escribió.

## A mano

Antes de empezar, el checkout tiene que estar bootstrapeado: `.env` con su
`COMPOSE_PROJECT_NAME`, los configs reales copiados de sus `.example`, y los secrets
cargados —incluidos `restic_password` y `restic_r2_credentials`, que tienen que ser
**los del repositorio de origen**, o no hay nada que leer.

`RESTIC_REPOSITORY` en `stacks/backup/config/r2.env` apunta al repositorio de origen,
letra por letra.

## Comandos

```bash
make postgres-up                 # el motor tiene que estar arriba: el dump entra por psql
make restore                     # o SNAPSHOT=<id> para uno que no sea el último
make odoo-up
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
make backup-verify
make odoo-verify
```

Y lo que ninguna verificación automática cubre: **abrir la aplicación y comprobar que un
adjunto se descarga**. Es lo único que prueba que las dos mitades corresponden entre sí.
