# Levantar desarrollo

## Cuándo se usa

Para probar localmente una feature de addons antes de publicarla en staging.

## Objetivo

Un checkout local aislado que recibe candidatos de una rama `feat/*`, ejecuta su propia imagen Odoo y no escribe backups productivos. No existe una rama operativa `19.0-dev` ni un runtime de desarrollo obligatorio en el servidor.

## Flujo rápido

1. Crear o seleccionar la feature local que se quiere probar.
2. Preparar el checkout, secretos y configuración local.
3. Sincronizar addons desde esa feature, resolver dependencias y construir la imagen.
4. Levantar el runtime y ejecutar `verify`.

## A mano

En la máquina de desarrollo, creá una rama `feat/<nombre>` en cada repositorio de addons que cambies. Copiá `runtime/desarrollo/compose.env.example` a `runtime/desarrollo/compose.env`, completá los valores privados y elegí la edición cambiando solo `ODOO_EDITION` y `TAG`. Ejecutá siempre los comandos con `ENTORNO=desarrollo` y `ADDONS_REF=feat/<nombre>`; el selector rechaza cualquier referencia que no tenga ese prefijo.

## Comandos

```bash
cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env
ENTORNO=desarrollo make secrets-init config-init
sudo ENTORNO=desarrollo make secrets-perms
ENTORNO=desarrollo make host-verify
ENTORNO=desarrollo ADDONS_REF=feat/mi-cambio make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make up
ENTORNO=desarrollo make verify
```

Cuando cambie la feature, repetí `ADDONS_REF=feat/mi-cambio make repo-sync`, `addons-deps` si cambiaron manifiestos y `build`. El webhook no usa `feat/*`: solo sincroniza candidatos de staging y producción, y nunca altera la imagen Actual ni reinicia contenedores.

Para cambiar de Community a Enterprise, editá el `compose.env` plano con `ODOO_EDITION=enterprise` y `TAG=19.0-ee-YYYY-MM-DD`, construí la imagen y validá el runtime aislado antes de aplicar. El preflight solo consulta módulos instalados; no los instala, actualiza ni desinstala.

Para aplicar una imagen validada:

```bash
ENTORNO=desarrollo make validate-image NOTE="prueba manual"
ENTORNO=desarrollo make apply-image
```

## Verificación

`ENTORNO=desarrollo make verify` debe mostrar el proyecto propio, la imagen Actual y ninguna referencia a `/mnt/extra-addons`. Desarrollo no incluye backup por defecto; si necesitás repetir la siembra, descartá el runtime local y volvé a levantarlo. Una vez validada la feature, publicala de forma controlada en `19.0-stag` para continuar la prueba en el servidor.
