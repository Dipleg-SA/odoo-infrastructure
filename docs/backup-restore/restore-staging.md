# Restore de staging

## Cuándo se usa

Para sembrar o volver a sembrar staging con un snapshot válido de producción.

## Objetivo

Restaurar base y filestore en staging sin modificar producción ni seleccionar una imagen histórica.

## Preparación

Confirmá `ENTORNO=staging`, las credenciales Restic de solo lectura y que Odoo esté detenido. El restore reemplaza los datos actuales de staging.

## Flujo por stacks

### 1. Edge

```bash
ENTORNO=staging make nginx-up
ENTORNO=staging make nginx-verify
ENTORNO=staging make cloudflared-up
ENTORNO=staging make cloudflared-verify
```

### 2. PostgreSQL y restore

```bash
ENTORNO=staging make postgres-up
ENTORNO=staging make postgres-verify
ENTORNO=staging make restore SNAPSHOT=latest
```

El restore recupera base, filestore y metadata del backup. Si el snapshot trae `images.json` legacy, se conserva como dato histórico y no cambia `ODOO_IMAGE`.

### 3. Odoo

Sincronizá candidatos, dependencias y la imagen antes de levantar Odoo:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
ENTORNO=staging make odoo-up
ENTORNO=staging make odoo-verify
```

### 4. Backup

```bash
ENTORNO=staging make backup-verify
```

Staging solo ofrece backup bajo el perfil `restore`; no ejecutes `backup-run` ni instales timers productivos.

### 5. Monitoring

No aplica: staging no incluye la capa de observabilidad.

## Validar una variante Community

Si el snapshot corresponde a Enterprise, restaurá primero con `ODOO_EDITION=enterprise`, retir&aacute; manualmente los módulos Enterprise y ejecutá:

```bash
ENTORNO=staging scripts/odoo-edition-check.sh --destino community
```

Después cambiá `ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`, construí la imagen Community y repetí la validación. El preflight bloquea una base incompatible; no convierte módulos ni modifica producción.
