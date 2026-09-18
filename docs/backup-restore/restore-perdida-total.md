# Restore de pérdida total

## Cuándo se usa

Cuando el servidor productivo no existe o sus datos locales son irrecuperables. Para sembrar staging, usá [restore-staging](restore-staging.md).

## Objetivo

Reconstruir el checkout, recuperar base y filestore desde un snapshot y levantar producción con una imagen Odoo reconstruida explícitamente.

## A mano

Recuperá `runtime/produccion/compose.env`, configs, secrets y
`runtime/addons/catalogo.txt`. El checkout Enterprise se reconstruye después bajo
`runtime/produccion/addons/enterprise`. `RESTIC_REPOSITORY` y las credenciales deben ser
las del repositorio de origen. Conservá el `COMPOSE_PROJECT_NAME` original.

El snapshot contiene base, filestore, la selección ejecutada y metadata del backup; no
contiene repositorios ni selecciona imágenes. Los commits registrados tienen que seguir
disponibles en sus remotos.

## Flujo de recuperación

### 1. Edge

Primero reconstruí Docker y el host; después prepará los servicios de borde:

```bash
ENTORNO=produccion make nginx-up
ENTORNO=produccion make nginx-verify
ENTORNO=produccion make cloudflared-up
ENTORNO=produccion make cloudflared-verify
```

### 2. PostgreSQL y restore

```bash
ENTORNO=produccion make postgres-up
ENTORNO=produccion make postgres-verify
ENTORNO=produccion make restore SNAPSHOT=latest
```

El restore exige Odoo detenido y Postgres activo. Recupera filestore, dump y metadata del backup; no ejecuta ninguna selección de imagen.

### 3. Odoo

Completá código, dependencias y configuración antes de levantar la aplicación:

```bash
ENTORNO=produccion make addons-runtime-init
ENTORNO=produccion make repo-sync
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
ENTORNO=produccion make odoo-up
ENTORNO=produccion make odoo-verify
```

### 4. Backup

```bash
ENTORNO=produccion make backup-up
ENTORNO=produccion make backup-verify
ENTORNO=produccion make backup-run
sudo ENTORNO=produccion make up-timers
```

### 5. Monitoring

```bash
ENTORNO=produccion make prometheus-up
ENTORNO=produccion make prometheus-verify
ENTORNO=produccion make loki-up
ENTORNO=produccion make loki-verify
ENTORNO=produccion make grafana-up
ENTORNO=produccion make grafana-verify
ENTORNO=produccion make alloy-up
ENTORNO=produccion make alloy-verify
```

## Edición Community/Enterprise

Conservá la edición y los commits ejecutados del snapshot durante el primer restore. Para
pasar a Community, retirá los módulos Enterprise en un entorno aislado, ejecutá el
preflight, cambiá `ODOO_EDITION`/`TAG`, construí una imagen Community y validá
nuevamente. La recuperación no usa rollback de imagen ni una imagen anterior.

## Verificación

```bash
ENTORNO=produccion make verify
```

Comprobá además que un adjunto se descargue desde la aplicación: es la prueba funcional de que base y filestore corresponden.
