# Actualizar módulo

## Cuándo se usa

Ya tenés un módulo declarado —propio o dentro de un fork— y necesitás cambiarle código, vista o dato. Cubre también la primera vez que ese módulo se instala en un entorno donde nunca corrió: el procedimiento es idéntico, solo cambia el último comando (`odoo-install` en vez de `odoo-update`).

Transversal a custom-addons, oca y third-party. No aplica a Enterprise sin acceso git — ver [crear-enterprise](../modulos/crear-enterprise.md).

## Objetivo

El cambio validado en staging y aplicado en producción.

## Comandos

**Desarrollo**, dentro del worktree del módulo:

```bash
cd addons/<categoría>/<repo>
git checkout -b feat/nombre-del-cambio
```

Desde acá `addons-sync` deja de tocar ese repositorio, y lo avisa cada vez que corre. Trabajás y probás en loop:

```bash
make odoo-update MODULES=<nombre_tecnico>
```

**Integración a staging.** La rama de staging es descartable en todo momento — nunca contiene nada que no exista además en una `feat/*` o en producción:

```bash
git checkout <rama>-stag
git reset --hard <rama>
git merge feat/nombre-del-cambio
git push --force origin <rama>-stag
```

**Traer y validar**, desde el checkout de staging en el servidor:

```bash
make addons-sync
make pydeps-check
```

Si el cambio agregó una dependencia Python nueva, `pydeps-check` lo va a marcar: `make pydeps-sync && docker compose build odoo` antes de seguir.

El servidor nunca mergea ni pushea, solo trae. Si `addons-sync` avisa que el `merge --ff-only` no avanzó (staging se reescribió con `--force`), nombra los dos comandos:

```bash
git -C addons/<categoría>/<repo> rebase origin/<rama>-stag       # integrar
git -C addons/<categoría>/<repo> reset --hard origin/<rama>-stag # descartar, si son descartables
```

El rebase es el default. El reset solo si esos commits locales son descartables.

**Promover**, de vuelta en tu checkout de development:

```bash
git checkout <rama>
git merge feat/nombre-del-cambio
git push origin <rama>
```

Sube exactamente lo que validaste, no lo que haya acumulado la rama de staging.

**Aplicar en producción:**

```bash
make addons-sync
make pydeps-check
make odoo-install MODULES=<nombre_tecnico>   # primera vez que este módulo se instala en este entorno
make odoo-update MODULES=<nombre_tecnico>    # cualquier otra vez
```

## Verificación

```bash
make addons        # limpio, en la rama esperada, en cada checkout
make odoo-modules   # en producción, versión nueva o módulo recién instalado
make verify
```

---

**Nota — qué corre en cada lado.** El servidor nunca hace `commit`/`merge`/`push`: solo `fetch`/`reset --hard`/`merge --ff-only` vía `addons-sync`, y `-i`/`-u` vía los `make` targets. Todo commit, merge y push pasa por tu máquina. Es deliberado: nada en el disco del servidor es irrecuperable — perder `addons/` entero se arregla con `make addons-sync`.

`make odoo-install`/`odoo-update` **detienen el servicio** mientras corren: es un paso explícito del operador, nunca algo que dispare el arranque del contenedor. Si el paso falla, el servicio se levanta igual y el comando reporta el error.
