# Levantar staging

## Cuándo se usa

Para sembrar y validar staging con datos de producción antes de promover una imagen.

## Objetivo

Un runtime aislado con ramas `19.0-stag`, SMTP desactivado y credencial Restic de solo lectura.

## A mano

Copiá `runtime/staging/compose.env.example` a `runtime/staging/compose.env`, cargá sus secretos y configuración, y usá siempre `ENTORNO=staging`.

## Comandos

```bash
cp runtime/staging/compose.env.example runtime/staging/compose.env
ENTORNO=staging make secrets-init config-init
sudo ENTORNO=staging make secrets-perms
ENTORNO=staging make host-verify
ENTORNO=staging make postgres-up
ENTORNO=staging make restore
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging ENTERPRISE_TAG=19.0-ee-YYYY-MM-DD make build
ENTORNO=staging make up
ENTORNO=staging make verify
```

`restore` reemplaza la base y el filestore de staging y recupera la procedencia del snapshot. Si se opera un módulo durante la validación, staging se descarta y se vuelve a sembrar antes de otro intento.

Para promover una fotografía ya validada:

```bash
ENTORNO=staging make validate-image NOTE="validación funcional"
ENTORNO=staging make apply-image
```

## Verificación

`ENTORNO=staging make verify` debe confirmar la imagen Actual, `ODOO_DISABLE_SMTP=1`, el certificado propio y la ausencia de timers de backup. `ENTORNO=staging make backup-run` debe fallar.
