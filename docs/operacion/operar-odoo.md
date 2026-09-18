# Operar Odoo

## Cuándo se usa

Para subir, bajar, reiniciar o inspeccionar Odoo dentro de un entorno explícito.

## Objetivo

Operar el servicio sin cambiar la imagen declarada ni tocar otros entornos.

## Flujo rápido

1. Elegir el entorno explícito.
2. Ejecutar la operación de Odoo y revisar sus logs.
3. Confirmar `ODOO_IMAGE` con `odoo-verify`.

## Comandos

```bash
ENTORNO=produccion make odoo-up
ENTORNO=produccion make odoo-down
ENTORNO=produccion make odoo-restart
ENTORNO=produccion make odoo-logs
ENTORNO=produccion make odoo-ps
```

La imagen se cambia editando la configuración de edición, sincronizando candidatos y
ejecutando `make build`. No se monta código de addons desde el host. Las operaciones de
módulos siguen [gestionar-modulo](../modulos/gestionar-modulo.md).

## Verificación

```bash
ENTORNO=produccion make odoo-verify
```

La verificación comprueba que la imagen local existe, que Compose usa `ODOO_IMAGE`, que
su procedencia coincide con edición y tag y que no monta `/mnt/extra-addons`.
