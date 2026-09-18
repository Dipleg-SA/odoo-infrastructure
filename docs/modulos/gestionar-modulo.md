# Gestionar módulos

## Cuándo se usa

Para instalar, actualizar o desinstalar módulos de forma manual sobre el `ODOO_IMAGE`
seleccionado de un entorno.

## Objetivo

Operar módulos mediante la API ORM, conservar el backup asociado y validar el resultado
antes de promover cambios de código.

## Flujo rápido

1. Confirmar catálogo, candidatos, entorno y `ODOO_IMAGE`.
2. Ejecutar la operación explícita sobre el módulo.
3. Verificar Odoo y conservar el backup si la operación afecta datos.

## A mano

El repositorio debe estar en el catálogo y el candidato sincronizado. Las operaciones
requieren `ENTORNO` y `MODULES`; nunca se disparan desde el webhook.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make odoo-up
ENTORNO=desarrollo make addons-install MODULES=mi_modulo
# o addons-update / addons-uninstall con MODULES explícitos
ENTORNO=desarrollo make verify
```

Después de promover el código por pull request, construí y validá staging antes de
repetir la operación manual allí:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make build
ENTORNO=staging make odoo-up
ENTORNO=staging make addons-update MODULES=mi_modulo
ENTORNO=staging make verify
```

Producción exige backup previo y aprobación funcional:

```bash
ENTORNO=produccion make backup-run
ENTORNO=produccion make addons-update MODULES=mi_modulo
ENTORNO=produccion make verify
```

## Verificación

Cada operación detiene Odoo, usa la API ORM y lo vuelve a levantar. Si la validación
falla, restaurá el backup asociado y reconstruí la imagen solo después de corregir los
candidatos o la configuración.
