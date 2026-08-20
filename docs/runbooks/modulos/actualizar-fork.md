# Actualizar fork

## Cuándo se usa

Salió una versión nueva del módulo original (OCA o de un proveedor) y la querés traer a tu fork — con o sin un parche propio ya aplicado sobre alguno de los módulos que trae esa actualización. Requiere haber trackeado `upstream` al crear el fork (ver [crear-fork](crear-fork.md)).

## Objetivo

Tu fork al día con `upstream`, validado en staging antes de producción.

## Comandos

```bash
git -C addons/.repos/<repo>.git fetch upstream

git checkout <rama>-stag
git merge upstream/<rama>
```

**Si aparece un conflicto**, es porque ya tenías un `feat/*` propio mergeado sobre alguno de los módulos que trae esta actualización. Resolvelo acá, a mano, con criterio de negocio — es el único paso de este procedimiento que puede pedir juicio en vez de solo comandos, y no hay atajo automático.

```bash
git push --force origin <rama>-stag
```

Traer y validar en el servidor de staging:

```bash
make addons-sync
```

Si `addons-sync` avisa que el `merge --ff-only` no avanzó en línea recta (staging se reescribió con `--force`), nombra los dos comandos posibles: `git rebase origin/<rama>-stag` para integrar, o `git reset --hard origin/<rama>-stag` si los commits locales son descartables.

Probá de verdad en staging. Recién validado, promover:

```bash
git checkout <rama>
git merge upstream/<rama>   # o merge de la rama de staging, si hubo que resolver un conflicto ahí
git push origin <rama>
```

Aplicar en producción:

```bash
make addons-sync
make pydeps-check
make odoo-update MODULES=<módulos-afectados>
```

## Verificación

```bash
make addons     # limpio, en la rama esperada, en cada checkout
make odoo-modules   # en producción, muestra la versión nueva
make verify
```
