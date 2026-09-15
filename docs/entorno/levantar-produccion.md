# Levantar producción

## Cuándo se usa

Para preparar o recuperar el runtime productivo de una línea mayor de Odoo.

## Objetivo

Producción ejecuta únicamente la imagen Actual declarada, conserva backup de base, filestore y procedencia, y opera con `ENTORNO=produccion` explícito.

## A mano

Copiá `runtime/produccion/compose.env.example` a `runtime/produccion/compose.env`, completá secretos, red, SMTP y R2. Nunca uses un `.env` raíz para elegir la composición.

## Comandos

```bash
cp runtime/produccion/compose.env.example runtime/produccion/compose.env
ENTORNO=produccion make secrets-init config-init
sudo ENTORNO=produccion make secrets-perms
ENTORNO=produccion make host-verify
ENTORNO=produccion make cert-issue
ENTORNO=produccion make repo-sync
ENTORNO=produccion make addons-deps
ENTORNO=produccion ENTERPRISE_TAG=19.0-ee-YYYY-MM-DD make build
ENTORNO=produccion make up
ENTORNO=produccion make backup-run
sudo ENTORNO=produccion make up-timers
ENTORNO=produccion make verify
```

`apply-image` crea el backup previo cuando la composición incluye backup, promueve Nueva y levanta Odoo con la referencia Actual. No instala ni actualiza módulos automáticamente.

```bash
ENTORNO=produccion make validate-image NOTE="validación de staging aprobada"
ENTORNO=produccion make apply-image
```

## Verificación

`ENTORNO=produccion make verify` debe informar tag, digest y procedencia de Actual, además del estado de backups y timers. Antes de una operación de módulos, confirmá un backup reciente; después de operar módulos, el rollback solo de imagen queda bloqueado.
