# Gestionar ramas de staging

## Cuándo se usa

Para publicar una feature en staging, promover un conjunto validado a producción o descartar cambios acumulados en staging.

## Objetivo

Mantener `19.0-stag` como el conjunto que se prueba en el servidor y `19.0` como la rama estable de producción. Las ramas `feat/*` se trabajan localmente; no existe una rama operativa `19.0-dev`.

## Flujo rápido

1. Desarrollar y probar localmente en `feat/<nombre>`.
2. Integrar o publicar esa feature de forma controlada sobre `19.0-stag` y validarla completa en staging.
3. Promover `19.0-stag` hacia `19.0` mediante PR aprobado; luego sincronizar y verificar producción.

## A mano

`19.0-stag` puede contener más de una feature. Por eso cada validación y cada PR de promoción cubren todo su delta con `19.0`. No se exige un PR individual para entrar a staging, pero sí se debe revisar conscientemente la base actual antes de integrarla.

Si se decide descartar cambios de staging, el término correcto es **realinear staging con producción**: hacer que `19.0-stag` coincida exactamente con `19.0`. No es un rebase. La operación reescribe la rama remota solo cuando hay commits que descartar, y siempre conserva antes una referencia de respaldo publicada.

La rama remota `19.0-stag` debe quedar protegida: rechazá force-push y borrado, y limitá los pushes directos al operador o automatización autorizados. No actives una regla que exija PR para cada actualización de staging, porque contradice este flujo. La realineación es la única excepción: se habilita de forma temporal para el operador autorizado, se ejecuta con respaldo y se vuelve a bloquear de inmediato.

## Comandos

Crear y probar una feature local:

```bash
git switch 19.0
git pull --ff-only origin 19.0
git switch -c feat/mi-cambio
# desarrollar y ejecutar las pruebas locales
```

Publicarla en staging sin PR intermedio:

```bash
git fetch origin --prune
git switch 19.0-stag
git pull --ff-only origin 19.0-stag
git merge --no-ff feat/mi-cambio
git push origin 19.0-stag
```

En el servidor, el push actualiza únicamente el candidato de staging. Construí, aplicá y validá manualmente la imagen del conjunto antes de abrir el PR `19.0-stag → 19.0`.

Si `19.0-stag` está detrás de `19.0` y no tiene commits propios, actualizala sin reescritura:

```bash
git fetch origin --prune
git switch 19.0-stag
git merge --ff-only origin/19.0
git push origin 19.0-stag
```

Para descartar commits de staging y realinearla exactamente con producción:

```bash
# Registrar la excepción temporal y habilitar force-push solo para esta operación.
git fetch origin --prune
git switch 19.0-stag
git branch backup/19.0-stag-YYYYMMDD-HHMM origin/19.0-stag
git push origin backup/19.0-stag-YYYYMMDD-HHMM
git reset --hard origin/19.0
git push --force-with-lease origin HEAD:19.0-stag
```

El último bloque es deliberadamente destructivo para la rama remota, pero el respaldo publicado permite recuperar los commits. Antes de habilitar la excepción, registrá el motivo, el operador, los SHAs anterior y destino y el nombre de `backup/19.0-stag-*`. Confirmá el nombre de la rama, el commit de respaldo y la diferencia antes de ejecutarlo. Al terminar, restaurá la regla que bloquea force-push y borrados. Después, sincronizá staging para reemplazar su candidato; no se construye ni aplica una imagen automáticamente.

## Verificación

Antes de promover, verificá que el PR muestre el delta completo y que la imagen Actual de staging tenga una validación exitosa. Después de fusionarlo, ejecutá `ENTORNO=produccion make repo-sync` y `ENTORNO=produccion make promotion-verify` antes de construir producción.

Tras una realineación, estos refs deben coincidir:

```bash
git fetch origin --prune
git rev-parse origin/19.0-stag
git rev-parse origin/19.0
```

Guardá la referencia `backup/19.0-stag-*` hasta que la nueva validación haya concluido.

En la configuración del proveedor Git, verificá que la regla de `19.0-stag` muestre force-push y borrado bloqueados, sin requisito de PR para los pushes autorizados. Tras una realineación, confirmá que esa protección volvió a estar activa y conservá el registro de la excepción junto al backup publicado.
