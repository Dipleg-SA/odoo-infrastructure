# Restore de staging

## Cuándo se usa

Para sembrar o volver a sembrar staging con el último snapshot válido de producción.

## Objetivo

Restaurar base, filestore y procedencia de imágenes en staging sin modificar producción.

## Flujo rápido

1. Confirmar credenciales de solo lectura y detener Odoo.
2. Restaurar el snapshot y sincronizar código y dependencias.
3. Construir, levantar y verificar staging.

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
ENTORNO=staging make build
ENTORNO=staging make up
```

El restore recupera `Actual` y `Anterior` desde `runtime/staging/state/images.json`; la imagen candidata de staging se aplica después de construirla y validarla.

## Verificación

```bash
ENTORNO=staging make verify
ENTORNO=staging make addons-modules
```

No ejecutes `backup-run` en staging. Si la validación incluyó operaciones de módulos, descartá y restaurá nuevamente antes de continuar.

## Validar una variante Community

Si el snapshot corresponde a Enterprise, mantené temporalmente `ODOO_EDITION=enterprise` y su `TAG` mientras restaurás la procedencia. Sobre la copia aislada, retiră manualmente los módulos Enterprise y verificá que la base quede sin ellos:

```bash
ENTORNO=staging scripts/odoo-edition-check.sh --destino community
ENTORNO=staging make verify
```

Después cambiá únicamente `ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD` en `runtime/staging/compose.env`, construí la imagen Community y repetí la validación. El preflight bloquea la imagen si encuentra módulos Enterprise instalados o si falta el inventario Enterprise histórico; no convierte módulos ni modifica producción.
