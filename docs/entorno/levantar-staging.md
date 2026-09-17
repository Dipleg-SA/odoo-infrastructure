# Levantar staging

## Cuándo se usa

Para sembrar y validar staging con datos de producción antes de promover una imagen.

## Objetivo

Un runtime aislado que recibe exclusivamente `19.0-stag`, con SMTP desactivado y credencial Restic de solo lectura.

## Flujo rápido

1. Preparar entorno, secretos y configuración.
2. Restaurar el snapshot elegido, sincronizar `19.0-stag` y construir la imagen.
3. Aplicar la imagen de staging, validar el conjunto completo y ejecutar `verify`.

## A mano

Copiá las tres plantillas antes de iniciar el runtime. `runtime/staging/compose.env` declara `ADDONS_REF=19.0-stag`; esa rama debe existir en todos los dominios del catálogo y staging nunca la crea ni la sobrescribe.

## Comandos

```bash
cp runtime/staging/compose.env.example runtime/staging/compose.env
cp runtime/addons/catalogo.txt.example runtime/addons/catalogo.txt
cp runtime/addons/requirements.txt.example runtime/addons/requirements.txt
ENTORNO=staging make secrets-init config-init
sudo ENTORNO=staging make secrets-perms
ENTORNO=staging make host-verify
ENTORNO=staging make postgres-up
ENTORNO=staging make restore
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
ENTORNO=staging make up
ENTORNO=staging make verify
```

`restore` reemplaza la base y el filestore de staging y recupera la procedencia del snapshot. `19.0-stag` puede contener varias features: la prueba y su resultado aplican al conjunto completo frente a `19.0`, no solo a la última feature incorporada. Si se opera un módulo durante la validación, staging se descarta y se vuelve a sembrar antes de otro intento.

Para validar Community→Enterprise, cambiá el par plano a `ODOO_EDITION=enterprise` y `TAG=19.0-ee-YYYY-MM-DD`, restaurá una copia de producción y ejecutá el preflight antes de levantar la imagen. La validación de staging no modifica producción ni instala módulos automáticamente; esa aplicación queda para el paso controlado posterior.

Al terminar las pruebas funcionales, aplicá la imagen construida y registrá la evidencia sobre su `Actual`:

```bash
ENTORNO=staging make apply-image
ENTORNO=staging make validate-image NOTE="validación funcional del conjunto 19.0-stag"
```

La nota debe identificar la revisión o conjunto probado y el resultado. Si la validación falla, no abras ni apruebes el PR `19.0-stag → 19.0`; corregí el conjunto o realineá staging de manera explícita antes de comenzar otra prueba.

## Verificación

`ENTORNO=staging make verify` debe confirmar la imagen Actual, `ODOO_DISABLE_SMTP=1`, el certificado propio y la ausencia de timers de backup. `ENTORNO=staging scripts/image-state.sh show` debe mostrar `validation.result: ok` asociada a esa Actual. `ENTORNO=staging make backup-run` debe fallar.
