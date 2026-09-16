# Simulacro de restore

## Cuándo se usa

Periódicamente, y **cada vez que se siembra prueba**. Las dos son la misma operación,
y por eso el ejercicio que si no siempre se posterga tiene ocasión natural.

## Objetivo

Comprobar que el respaldo restaura de verdad. Un backup sin probar no es un backup: el
repositorio puede estar corrupto, la credencial puede haber vencido, o el snapshot
puede traer una sola de las dos mitades del estado.

## Flujo rápido

1. Preparar staging con credenciales de solo lectura.
2. Restaurar el último snapshot siguiendo `restore-staging`.
3. Entrar a Odoo y abrir un registro con adjuntos.
4. Ejecutar la verificación del backup y confirmar que un adjunto se descarga.

## A mano

Un checkout de staging con `COMPOSE_PROJECT_NAME` **distinto** al de producción, el
repositorio R2 de producción configurado y secrets de restic con permiso de solo
lectura. Seguí [restore-staging](restore-staging.md), que prepara el restore sin
activar timers de backup.

Restaurar en una máquina distinta de la de origen es el simulacro más fuerte: prueba
que el respaldo es portable y no depende en secreto de algo que solo existe en el
servidor que lo escribió.

## Comandos

El procedimiento completo está en [restore-staging](restore-staging.md). Usá el último
snapshot salvo que el simulacro tenga como objetivo probar uno específico.

## Verificación

```bash
make backup-verify
```

Y lo que decide si el simulacro sirvió: **entrar a la aplicación, abrir un registro con
adjuntos y descargar uno**. Que la base levante prueba la mitad; que el adjunto abra
prueba que las dos mitades corresponden al mismo momento.

Si el ejercicio falla, el hallazgo es más valioso que el simulacro: significa que el
backup nocturno venía dando verde sobre algo que no restauraba.
