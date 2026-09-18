# Levantar staging

## Cuándo se usa

Para sembrar y validar staging con datos de producción antes de continuar el código hacia producción.

## Objetivo

Un runtime aislado que publica exclusivamente `19.0-stag` en
`runtime/staging/addons/custom`, conserva su propio checkout Enterprise, mantiene SMTP
desactivado y usa credenciales Restic de solo lectura.

## Preparación

```bash
cp runtime/staging/compose.env.example runtime/staging/compose.env
cp runtime/addons/catalogo.txt.example runtime/addons/catalogo.txt
cp runtime/addons/requirements.override.txt.example runtime/addons/requirements.override.txt

ENTORNO=staging make secrets-init config-init
sudo ENTORNO=staging make secrets-perms
ENTORNO=staging make secrets-check
ENTORNO=staging make host-verify
ENTORNO=staging make addons-runtime-init
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
```

`make build` deja `ODOO_IMAGE` apuntando a la imagen de staging construida. La validación funcional es manual y no requiere una ranura de imagen.

Para una revisión posterior sin cambios de base, edición ni dependencias:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make odoo-restart
ENTORNO=staging make odoo-verify
```

Si `addons-deps` cambia una huella, construí antes una imagen nueva. Un cambio exclusivo
de código recrea Odoo sin build; staging nunca instala ni actualiza módulos por publicar
el candidato.

## Flujo por stacks

### 1. Edge

```bash
ENTORNO=staging make nginx-up
ENTORNO=staging make nginx-verify
ENTORNO=staging make cloudflared-up
ENTORNO=staging make cloudflared-verify
```

Dnsmasq no está incluido en staging.

### 2. PostgreSQL

```bash
ENTORNO=staging make postgres-up
ENTORNO=staging make postgres-verify
```

Para sembrar staging, restaurá después de comprobar PostgreSQL y antes de levantar Odoo:

```bash
ENTORNO=staging make restore SNAPSHOT=latest
```

### 3. Odoo

```bash
ENTORNO=staging make odoo-up
ENTORNO=staging make odoo-verify
```

No continúes si `postgres-verify` u `odoo-verify` falla. Staging nunca instala ni actualiza módulos automáticamente.

### 4. Backup

El servicio permanente de backup no aplica a staging; el servicio existe bajo el perfil `restore` para la siembra. Verificá el repositorio sin dejar un timer productivo:

```bash
ENTORNO=staging make backup-verify
```

No ejecutes `backup-run` ni instales timers de backup en staging.

### 5. Monitoring

No aplica: staging no incluye la capa de observabilidad.

## Cambios de edición

Para validar Community→Enterprise, cambiá el par `ODOO_EDITION`/`TAG`, restaurá una copia aislada y ejecutá `scripts/odoo-edition-check.sh --destino community|enterprise` antes de levantar Odoo. El preflight bloquea una combinación incompatible con los módulos instalados.

## Verificación final

```bash
ENTORNO=staging make verify
ENTORNO=staging make addons-modules
```

La evidencia funcional identifica la revisión o el conjunto completo de `19.0-stag`. Si la prueba incluyó operaciones de módulos, volvé a sembrar staging antes de otro intento.

## Verificación aislada sin Cloudflare

Para ensayar staging en el servidor sin interferir con el stack activo, copiá el checkout a una ruta de verificación y seguí [`verificar-runtime-aislado.md`](verificar-runtime-aislado.md). La copia usa identidad, puertos, volúmenes y hostname propios; restaura un snapshot exacto y no ejecuta `backup-run` ni timers. En esta modalidad Cloudflare queda fuera de alcance y la verificación se hace por Nginx/HTTPS local.
