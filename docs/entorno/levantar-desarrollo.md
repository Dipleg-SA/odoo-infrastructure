# Levantar desarrollo

## Cuándo se usa

Para levantar o volver a crear el runtime de desarrollo del checkout canónico.

## Objetivo

Un entorno aislado que recibe candidatos de `19.0-dev`, ejecuta su propia imagen Odoo y no escribe backups productivos.

## Flujo rápido

1. Preparar entorno, secretos y configuración.
2. Sincronizar addons, resolver dependencias y construir la imagen.
3. Levantar el runtime y ejecutar `verify`.

## A mano

Copiá `runtime/desarrollo/compose.env.example` a `runtime/desarrollo/compose.env`, completá los valores privados y elegí la edición cambiando solo `ODOO_EDITION` y `TAG`. Ejecutá siempre los comandos con `ENTORNO=desarrollo`.

## Comandos

```bash
cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env
ENTORNO=desarrollo make secrets-init config-init
sudo ENTORNO=desarrollo make secrets-perms
ENTORNO=desarrollo make host-verify
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make up
ENTORNO=desarrollo make verify
```

Cuando llega un candidato nuevo, repetí `repo-sync`, `addons-deps` si cambiaron manifiestos y `build`. El webhook no altera la imagen Actual ni reinicia contenedores.

Para cambiar de Community a Enterprise, editá el `compose.env` plano con `ODOO_EDITION=enterprise` y `TAG=19.0-ee-YYYY-MM-DD`, construí la imagen y validá el runtime aislado antes de aplicar. El preflight solo consulta módulos instalados; no los instala, actualiza ni desinstala.

Para aplicar una imagen validada:

```bash
ENTORNO=desarrollo make validate-image NOTE="prueba manual"
ENTORNO=desarrollo make apply-image
```

## Verificación

`ENTORNO=desarrollo make verify` debe mostrar el proyecto propio, la imagen Actual y ninguna referencia a `/mnt/extra-addons`. Desarrollo no incluye backup por defecto; si necesitás repetir la siembra, descartá el runtime y volvé a levantarlo.
