# Operar backups

## Cuándo se usa

Para inspeccionar el contenedor de backup o ejecutar un backup y su verificación.

## Objetivo

Conservar base, filestore y procedencia de Actual/Anterior en el mismo snapshot de producción.

## Comandos

```bash
ENTORNO=produccion make backup-up
ENTORNO=produccion make backup-run
ENTORNO=produccion make backup-integrity
ENTORNO=produccion make backup-verify
ENTORNO=produccion make backup-logs
```

El backup registra `runtime/produccion/state/meta/images.json` junto con `addons.txt`. `apply-image` ejecuta el backup previo cuando corresponde.

Para restaurar en staging:

```bash
ENTORNO=staging make restore SNAPSHOT=latest
```

Para una restauración productiva, detené Odoo, conservá el snapshot asociado a la promoción y ejecutá el procedimiento de restore aprobado. El script recupera la procedencia e identifica la imagen Actual restaurada.

## Verificación

`ENTORNO=produccion make backup-verify` debe confirmar snapshots, base y filestore, registro de addons y procedencia de imágenes. Staging solo lee el repositorio y no ejecuta `backup-run`.
