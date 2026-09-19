# Gestionar módulos

## Cuándo se usa

Para instalar, actualizar o desinstalar módulos de forma manual sobre la imagen y los
addons montados del entorno.

## Objetivo

Operar módulos mediante la API ORM, conservar el backup asociado y validar el resultado
antes de promover cambios de código.

## Flujo rápido

1. Confirmar catálogo, integridad, selección cargada y compatibilidad de `ODOO_IMAGE`.
2. Ejecutar la operación explícita sobre el módulo.
3. Verificar Odoo y conservar el backup si la operación afecta datos.

## A mano

El repositorio debe estar en el catálogo y el candidato sincronizado. Las operaciones
requieren `ENTORNO` y `MODULES`; nunca se disparan desde el webhook.
El runner adquiere el mismo lock que sincronización y webhook, ejecuta el preflight
antes de detener Odoo y recrea el contenedor con `up -d --force-recreate` al finalizar.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make odoo-restart
ENTORNO=desarrollo make addons-install MODULES=mi_modulo
# o addons-update / addons-uninstall con MODULES explícitos
ENTORNO=desarrollo make verify
```

Después de promover el código por pull request, construí y validá staging antes de
repetir la operación manual allí:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make odoo-restart
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

Cada operación valida árbol, `odoo_base` y huellas antes de detener Odoo, usa la API ORM
y lo recrea al terminar incluso ante un error funcional. Si el preflight exige build,
construí antes de operar. Si la validación funcional falla, restaurá el backup asociado;
no edites el árbol montado ni automatices una operación correctiva.
