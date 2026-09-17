# Operar backups

## Cuándo se usa

Para inspeccionar el contenedor de backup o ejecutar un backup y su verificación.

## Objetivo

Conservar base, filestore y procedencia de Actual/Anterior en el mismo snapshot de producción.

## Flujo rápido

1. Levantar la capa de backup si está detenida.
2. Ejecutar la operación requerida y revisar sus logs.
3. Confirmar el snapshot con `backup-verify`.

## A mano

No requiere pasos manuales adicionales; las operaciones se ejecutan con `ENTORNO`
explícito y los restores siguen sus procedimientos específicos.

## Comandos

```bash
ENTORNO=produccion make backup-up
ENTORNO=produccion make backup-run
ENTORNO=produccion make backup-integrity
ENTORNO=produccion make backup-verify
ENTORNO=produccion make backup-logs
```

El backup registra `runtime/produccion/state/meta/images.json` junto con la procedencia de `runtime/addons/catalogo.txt`. `apply-image` ejecuta el backup previo cuando corresponde.

Para restaurar en staging:

```bash
ENTORNO=staging make restore SNAPSHOT=latest
```

Para una restauración productiva, detené Odoo, conservá el snapshot asociado a la promoción y ejecutá el procedimiento de restore aprobado. El script recupera la procedencia e identifica la imagen Actual restaurada.

## Verificación

`ENTORNO=produccion make backup-verify` debe confirmar snapshots, base y filestore, registro de addons y procedencia de imágenes. Staging solo lee el repositorio y no ejecuta `backup-run`.
