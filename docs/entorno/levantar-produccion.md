# Levantar producción

## Cuándo se usa

Para preparar o recuperar el runtime productivo de una línea mayor de Odoo.

## Objetivo

Producción ejecuta únicamente la imagen Actual declarada, conserva backup de base, filestore y procedencia, y opera con `ENTORNO=produccion` explícito.

## Flujo rápido

1. Preparar entorno, secretos, configuración, host y certificado.
2. Después del PR aprobado, sincronizar `19.0`, verificar la equivalencia con staging y construir la imagen aprobada.
3. Levantar Odoo, ejecutar un backup inicial, activar timers y verificar.

## A mano

Copiá `runtime/produccion/compose.env.example` a `runtime/produccion/compose.env`, completá secretos, red, SMTP y R2. Elegí la edición cambiando solo `ODOO_EDITION` y `TAG`; nunca uses un `.env` raíz para elegir la composición.

## Comandos

```bash
cp runtime/produccion/compose.env.example runtime/produccion/compose.env
ENTORNO=produccion make secrets-init config-init
sudo ENTORNO=produccion make secrets-perms
ENTORNO=produccion make host-verify
ENTORNO=produccion make cert-issue
# Después de fusionar el PR 19.0-stag → 19.0.
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
ENTORNO=produccion make up
ENTORNO=produccion make backup-run
sudo ENTORNO=produccion make up-timers
ENTORNO=produccion make verify
```

El PR `19.0-stag → 19.0` debe estar aprobado y contener el conjunto validado en staging. Después de fusionarlo, `repo-sync` publica los candidatos de `19.0` y `promotion-verify` compara sus árboles, edición y procedencia Enterprise contra la imagen Actual validada de staging. Si falla, detené el corte: no construyas ni apliques una imagen productiva hasta corregir la divergencia o repetir la validación.

`apply-image` crea el backup previo cuando la composición incluye backup, registra su snapshot asociado, ejecuta el preflight de solo lectura ante un cambio de edición, promueve Nueva y levanta Odoo con la referencia Actual. No instala ni actualiza módulos automáticamente. En Community→Enterprise, el backup y la imagen Community anterior quedan disponibles antes de cualquier operación manual de módulos.

```bash
ENTORNO=produccion make apply-image
ENTORNO=produccion make validate-image NOTE="validación de staging aprobada"
```

## Verificación

`ENTORNO=produccion make promotion-verify` debe terminar correctamente antes de `make build`. Después de aplicar, `ENTORNO=produccion make verify` debe informar tag, digest y procedencia de Actual, además del estado de backups y timers. Antes de una operación de módulos, confirmá un backup reciente; después de operar módulos, el rollback solo de imagen queda bloqueado.
