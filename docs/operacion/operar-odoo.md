# Operar Odoo

## Cuándo se usa

Para subir, bajar, reiniciar o inspeccionar Odoo dentro de un entorno explícito.

## Objetivo

Operar el servicio sin cambiar la imagen declarada ni tocar otros entornos.

## Comandos

```bash
ENTORNO=produccion make odoo-up
ENTORNO=produccion make odoo-down
ENTORNO=produccion make odoo-restart
ENTORNO=produccion make odoo-logs
ENTORNO=produccion make odoo-ps
```

Aplicar o revertir una imagen se hace con `apply-image` o `rollback-image`; no se usa `docker compose build` ni se monta código de addons desde el host.

## Verificación

```bash
ENTORNO=produccion make odoo-verify
```

La verificación informa Actual, digest y procedencia, comprueba que Compose usa esa referencia y rechaza `/mnt/extra-addons`. Las operaciones de módulos siguen [gestionar-modulo](../modulos/gestionar-modulo.md).
