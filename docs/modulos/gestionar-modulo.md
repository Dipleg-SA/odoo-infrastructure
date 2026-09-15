# Gestionar módulos

## Cuándo se usa

Para instalar, actualizar o desinstalar módulos de forma manual sobre la imagen Actual de un entorno.

## Objetivo

Operar módulos con una fotografía identificable, registrar el impacto sobre la reversión y validar el flujo antes de promover.

## A mano

El repositorio debe estar en el catálogo y el candidato sincronizado. Las operaciones requieren `ENTORNO` y `MODULES`; nunca se disparan desde el webhook.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make addons-install MODULES=mi_modulo
# o addons-update / addons-uninstall con MODULES explícitos
ENTORNO=desarrollo make verify
```

Promové el commit por pull request, construí y aplicá una imagen en staging, y repetí la operación manual allí:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make build
ENTORNO=staging make apply-image
ENTORNO=staging make addons-update MODULES=mi_modulo
ENTORNO=staging make verify
```

Producción exige backup previo y una aprobación funcional del entorno anterior:

```bash
ENTORNO=produccion make backup-run
ENTORNO=produccion make addons-update MODULES=mi_modulo
```

## Verificación

Cada operación detiene Odoo, usa la API ORM y lo vuelve a levantar. Una operación exitosa registra `rollback_blocked`; si la validación falla, restaurá el backup asociado antes de recuperar la imagen.
