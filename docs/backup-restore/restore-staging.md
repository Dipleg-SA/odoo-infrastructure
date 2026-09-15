# Restore de staging

## Cuándo se usa

Para sembrar o volver a sembrar staging con el último snapshot válido de producción.

## Objetivo

Restaurar base, filestore y procedencia de imágenes en staging sin modificar producción.

## A mano

Confirmá `ENTORNO=staging`, la credencial Restic de solo lectura y que Odoo esté detenido. El restore reemplaza los datos actuales de staging.

## Comandos

```bash
ENTORNO=staging make backup-verify
ENTORNO=staging make odoo-down
ENTORNO=staging make postgres-up
ENTORNO=staging make restore SNAPSHOT=latest
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging ENTERPRISE_TAG=19.0-ee-YYYY-MM-DD make build
ENTORNO=staging make up
```

El restore recupera `Actual` y `Anterior` desde `state/meta/images.json`; la imagen candidata de staging se aplica después de construirla y validarla.

## Verificación

```bash
ENTORNO=staging make verify
ENTORNO=staging make addons-modules
```

No ejecutes `backup-run` en staging. Si la validación incluyó operaciones de módulos, descartá y restaurá nuevamente antes de continuar.
