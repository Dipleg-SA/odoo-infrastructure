# Validar código antes de producción

## Cuándo se usa

Antes de llevar el conjunto probado de staging a la rama estable y construir producción.

## Objetivo

Validar el código y la imagen seleccionada en cada entorno, sin mantener estados de
promoción de imágenes.

## Flujo rápido

1. Probar la feature localmente.
2. Restaurar y validar en staging el conjunto completo de `19.0-stag`.
3. Promover ese conjunto por PR y comprobar la equivalencia antes del build productivo.

## A mano

La validación funcional es manual. Si cambia `ODOO_EDITION`, ejecutá el preflight ORM en
cada entorno y no ejecutes operaciones funcionales desde el webhook.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make odoo-up
ENTORNO=desarrollo make verify

ENTORNO=staging make restore SNAPSHOT=latest
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
ENTORNO=staging make odoo-up
ENTORNO=staging make verify
```

Después de validar, abrí el PR `19.0-stag → 19.0`. Su revisión cubre todo el delta;
una feature adicional exige validar nuevamente el conjunto. Una vez fusionado y
sincronizados los candidatos productivos, ejecutá:

```bash
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
ENTORNO=produccion make odoo-up
```

El backup es la frontera de recuperación. Si una validación o una operación funcional
falla, restaurá el backup aprobado y reconstruí explícitamente la imagen con los
candidatos y la edición declarada.

## Verificación

```bash
ENTORNO=<entorno> make odoo-verify
ENTORNO=<entorno> make verify
```

`promotion-verify` debe confirmar que los árboles de addons, la edición y la
procedencia Enterprise de producción coinciden con lo validado en staging.
