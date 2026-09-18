# Operar Odoo

## Cuándo se usa

Para subir, bajar, reiniciar o inspeccionar Odoo dentro de un entorno explícito.

## Objetivo

Operar el servicio con la imagen declarada y los addons de su entorno, sin tocar otros
runtimes.

## Flujo rápido

1. Elegir el entorno explícito.
2. Ejecutar la operación de Odoo y revisar sus logs.
3. Confirmar imagen, mounts y selección cargada con `odoo-verify`.

## Comandos

```bash
ENTORNO=produccion make odoo-up
ENTORNO=produccion make odoo-down
ENTORNO=produccion make odoo-restart
ENTORNO=produccion make odoo-logs
ENTORNO=produccion make odoo-ps
```

`odoo-up` y `odoo-restart` ejecutan el preflight bajo lock y recrean con
`up -d --force-recreate`; no usan `docker compose restart`. Los addons llegan desde
`runtime/<entorno>/addons/{custom,enterprise}` como binds de solo lectura. Un candidato
nuevo queda pendiente hasta esta recreación y no dispara operaciones de módulos.

La imagen solo cambia mediante `make build` cuando difieren base, edición o dependencias.
Las operaciones funcionales siguen
[gestionar-modulo](../modulos/gestionar-modulo.md).

## Verificación

```bash
ENTORNO=produccion make odoo-verify
```

La verificación comprueba que la imagen local existe, que `odoo_base` y huellas
coinciden, que los mounts son los del entorno y que
`/tmp/odoo-addons-startup.json` no quedó detrás de los candidatos.
