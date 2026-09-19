# Levantar desarrollo

## Cuándo se usa

Para preparar y probar localmente los candidatos de una feature antes de publicarla en staging.

## Objetivo

Un runtime aislado que publica una rama `feat/*` en
`runtime/desarrollo/addons/custom`, monta su propio Enterprise cuando corresponde y no
ejecuta backups productivos.

## Preparación

```bash
cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env
cp runtime/addons/catalogo.txt.example runtime/addons/catalogo.txt
cp runtime/addons/requirements.override.txt.example runtime/addons/requirements.override.txt

ENTORNO=desarrollo make secrets-init config-init
sudo ENTORNO=desarrollo make secrets-perms
ENTORNO=desarrollo make secrets-check
ENTORNO=desarrollo make host-verify
ENTORNO=desarrollo make addons-runtime-init
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
```

En el bootstrap, `make build` construye Odoo y las imágenes auxiliares. Al terminar
correctamente deja `ODOO_IMAGE` apuntando a la imagen local construida. Los cambios
posteriores de código no repiten ese build si el preflight conserva base, edición y
huellas de dependencias.

## Flujo por stacks

### 1. Edge

```bash
ENTORNO=desarrollo make nginx-up
ENTORNO=desarrollo make nginx-verify
```

Cloudflared y dnsmasq no están incluidos en desarrollo.

### 2. PostgreSQL

```bash
ENTORNO=desarrollo make postgres-up
ENTORNO=desarrollo make postgres-verify
```

No continúes si `postgres-verify` falla.

### 3. Odoo

```bash
ENTORNO=desarrollo make odoo-up
ENTORNO=desarrollo make odoo-verify
```

`odoo-up` rechaza una referencia ausente, inicial, flotante o que no exista localmente.

### 4. Backup

No aplica: desarrollo no incluye el servicio de backup.

### 5. Monitoring

No aplica: desarrollo no incluye la capa de observabilidad.

## Cambio frecuente de código

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make odoo-restart
ENTORNO=desarrollo make odoo-verify
```

`repo-sync` publica la feature bajo `runtime/desarrollo/addons/custom`. Si
`addons-deps` cambia las huellas, el preflight de `odoo-restart` se detiene y exige
`make build`; si no cambian, recrea Odoo sin construir. La instalación o actualización
del módulo continúa siendo manual.

Para cambiar de Community a Enterprise, editá `ODOO_EDITION` y `TAG` en `runtime/desarrollo/compose.env`, construí una nueva imagen y ejecutá el preflight antes de levantar Odoo. El preflight solo consulta módulos instalados.

## Verificación final

```bash
ENTORNO=desarrollo make verify
```

La recuperación se hace desde los datos locales y una reconstrucción explícita de la imagen; los tags anteriores no forman parte del flujo operativo.
