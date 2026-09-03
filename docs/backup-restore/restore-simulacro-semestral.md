# Simulacro de restore

## Cuándo se usa

Periódicamente, y **cada vez que se siembra prueba**. Las dos son la misma operación,
y por eso el ejercicio que si no siempre se posterga tiene ocasión natural.

## Objetivo

Comprobar que el respaldo restaura de verdad. Un backup sin probar no es un backup: el
repositorio puede estar corrupto, la credencial puede haber vencido, o el snapshot
puede traer una sola de las dos mitades del estado.

## A mano

Un checkout con `COMPOSE_PROJECT_NAME` **distinto** al de producción, y sus secrets de
restic cargados con los del repositorio de origen.

Restaurar en una máquina distinta de la de origen es el simulacro más fuerte: prueba
que el respaldo es portable y no depende en secreto de algo que solo existe en el
servidor que lo escribió.

## Comandos

El procedimiento es el de [restore-perdida-total](restore-perdida-total.md), sin
diferencias — lo que cambia es la intención, no los comandos.

```bash
make postgres-up
make restore
make odoo-up
```

## Verificación

```bash
make backup-verify
```

Y lo que decide si el simulacro sirvió: **entrar a la aplicación, abrir un registro con
adjuntos y descargar uno**. Que la base levante prueba la mitad; que el adjunto abra
prueba que las dos mitades corresponden al mismo momento.

Si el ejercicio falla, el hallazgo es más valioso que el simulacro: significa que el
backup nocturno venía dando verde sobre algo que no restauraba.
