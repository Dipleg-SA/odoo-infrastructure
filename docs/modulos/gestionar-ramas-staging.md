# Gestionar ramas de staging

## Cuándo se usa

Para publicar una feature en staging, promover un conjunto validado a producción o
descartar cambios acumulados en staging.

## Objetivo

Mantener `19.0-stag` como el conjunto que se prueba en el servidor y `19.0` como la rama
estable de producción. Desarrollo declara una rama `feat/*`.

## Flujo rápido

1. Desarrollar y probar localmente en `feat/<nombre>`.
2. Integrar la feature sobre `19.0-stag` y validar el conjunto completo en staging.
3. Promover `19.0-stag` hacia `19.0` mediante PR aprobado.

## A mano

`19.0-stag` puede contener varias features. Cada validación y cada PR cubren todo su
delta con `19.0`. Si se descartan cambios, realineá staging con producción y publicá
antes una referencia Git de respaldo; no se automatiza una reconstrucción por ese hecho.

La rama remota debe bloquear force-push y borrado, salvo una excepción temporal para la
realineación ejecutada por el operador autorizado. Registrá motivo, operador, SHAs y
referencia de respaldo antes de habilitarla.

## Comandos

Crear y probar una feature local:

```bash
git switch 19.0
git pull --ff-only origin 19.0
git switch -c feat/mi-cambio
# desarrollar y ejecutar las pruebas locales
```

Publicarla en staging:

```bash
git fetch origin --prune
git switch 19.0-stag
git pull --ff-only origin 19.0-stag
git merge --no-ff feat/mi-cambio
git push origin 19.0-stag
```

En el servidor, construí y validá manualmente la imagen seleccionada:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make build
ENTORNO=staging make odoo-up
ENTORNO=staging make verify
```

Para descartar commits y realinear staging exactamente con producción, conservá una
referencia publicada y ejecutá la operación Git destructiva con `--force-with-lease`.
Después sincronizá el candidato y repetí build y validación; no se ejecutan solos.

## Verificación

Antes de promover, verificá el delta completo del PR y el `make verify` exitoso en
staging. Después de fusionarlo:

```bash
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
```

Tras una realineación, `origin/19.0-stag` y `origin/19.0` deben coincidir. Conservá la
referencia de respaldo hasta terminar la nueva validación.
