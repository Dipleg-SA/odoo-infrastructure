# Levantar desarrollo

## Cuándo se usa

Para preparar y probar localmente los candidatos de una feature antes de publicarla en staging.

## Objetivo

Un checkout aislado que recibe candidatos de una rama `feat/*`, construye una única imagen Odoo y no ejecuta backups productivos.

## Preparación

```bash
cp runtime/desarrollo/compose.env.example runtime/desarrollo/compose.env
cp runtime/addons/catalogo.txt.example runtime/addons/catalogo.txt
cp runtime/addons/requirements.override.txt.example runtime/addons/requirements.override.txt

ENTORNO=desarrollo make secrets-init config-init
sudo ENTORNO=desarrollo make secrets-perms
ENTORNO=desarrollo make secrets-check
ENTORNO=desarrollo make host-verify
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
```

`make build` construye Odoo y las imágenes auxiliares. Al terminar correctamente deja `ODOO_IMAGE` apuntando a la imagen local construida. No hay promoción ni rollback de imagen.

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

## Cambios de código o edición

Cuando cambie la feature, repetí `repo-sync`, `addons-deps` si cambiaron requisitos y `build`. El webhook no altera la imagen ni reinicia contenedores.

Para cambiar de Community a Enterprise, editá `ODOO_EDITION` y `TAG` en `runtime/desarrollo/compose.env`, construí una nueva imagen y ejecutá el preflight antes de levantar Odoo. El preflight solo consulta módulos instalados.

## Verificación final

```bash
ENTORNO=desarrollo make verify
```

La recuperación se hace desde los datos locales y una reconstrucción explícita de la imagen; los tags anteriores no forman parte del flujo operativo.
