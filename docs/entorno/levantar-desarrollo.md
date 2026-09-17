# Levantar desarrollo

## Cuándo se usa

Para preparar y probar localmente los candidatos de una feature antes de publicarla en staging.

## Objetivo

Un checkout local aislado que recibe candidatos de la rama `feat/*` declarada en su runtime, ejecuta su propia imagen Odoo y no escribe backups productivos. No existe una rama operativa `19.0-dev` ni un runtime de desarrollo obligatorio en el servidor.

## Flujo rápido

1. Preparar el checkout, catálogo, dependencias, secretos y configuración local.
2. Inicializar o reutilizar la feature declarada desde `19.0`.
3. Sincronizar addons, resolver dependencias y construir la imagen.
4. Levantar el runtime y ejecutar `verify`.

## A mano

Copiá las tres plantillas antes de iniciar el runtime. `ADDONS_REF` queda declarada en `runtime/desarrollo/compose.env`; si la rama no existe en un dominio del catálogo, `repo-sync` la crea desde `origin/19.0`. La credencial de esta máquina necesita permiso para crear ramas `feat/*`; staging y producción no reciben ese permiso.

## Comandos

```bash
cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env
cp runtime/addons/catalogo.txt.example runtime/addons/catalogo.txt
cp runtime/addons/requirements.override.txt.example runtime/addons/requirements.override.txt
ENTORNO=desarrollo make secrets-init config-init
sudo ENTORNO=desarrollo make secrets-perms
ENTORNO=desarrollo make host-verify
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make up
ENTORNO=desarrollo make verify
```

Cuando cambie la feature, repetí `ENTORNO=desarrollo make repo-sync`, `addons-deps` si cambiaron requisitos y `build`. Los repositorios declaran sus dependencias en `requirements.txt`; el archivo `requirements.override.txt` queda solo para excepciones del deployment. El webhook no usa `feat/*`: solo sincroniza candidatos de staging y producción, y nunca altera la imagen Actual ni reinicia contenedores.

Para cambiar de Community a Enterprise, editá el `compose.env` plano con `ODOO_EDITION=enterprise` y `TAG=19.0-ee-YYYY-MM-DD`, construí la imagen y validá el runtime aislado antes de aplicar. El preflight solo consulta módulos instalados; no los instala, actualiza ni desinstala.

Para aplicar una imagen validada:

```bash
ENTORNO=desarrollo make validate-image NOTE="prueba manual"
ENTORNO=desarrollo make apply-image
```

## Verificación

`ENTORNO=desarrollo make verify` debe mostrar el proyecto propio, la imagen Actual y ninguna referencia a `/mnt/extra-addons`. Desarrollo no incluye backup por defecto; si necesitás repetir la siembra, descartá el runtime local y volvé a levantarlo. Una vez validada la feature, publicala de forma controlada en `19.0-stag` para continuar la prueba en el servidor.
