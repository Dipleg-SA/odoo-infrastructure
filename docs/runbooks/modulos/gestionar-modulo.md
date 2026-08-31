# Gestionar módulo

## Cuándo se usa

Tres momentos del mismo módulo: **crearlo** (necesitás uno nuevo dentro de un repositorio ya declarado y sincronizado), **actualizarlo** (le vas a cambiar código, vista o dato — cubre también la primera vez que se instala en un entorno donde nunca corrió) o **eliminarlo** (ya no cumple una función y lo sacás del árbol).

Transversal a custom-addons, oca y third-party. No aplica a Odoo Enterprise sin acceso git — ver [crear-enterprise](crear-enterprise.md).

## Objetivo

El módulo con el cambio que corresponda —esqueleto nuevo, código actualizado, o ausencia total— validado en staging y aplicado en producción.

---

## Crear

Ya tenés un repositorio declarado y sincronizado (ver [gestionar-fork § Crear](gestionar-fork.md#crear)) y necesitás un módulo nuevo adentro. Es el mismo procedimiento sin importar el origen del repositorio contenedor — un módulo nuevo dentro de tu propio repo o dentro de un fork de terceros nace igual.

**A mano.** Decidir el nombre técnico (`snake_case`). Tenelo presente contra la precedencia entre categorías si otro módulo en otra categoría ya usa ese nombre (ver la nota al final de [gestionar-fork](gestionar-fork.md)).

### Comandos

```bash
cd addons/<categoría>/<repo> && git checkout -b feat/<nombre-del-modulo> && cd -
```

**Generar el esqueleto directo en `addons/<categoría>/<repo>/<nombre_tecnico>/`** — archivos de host, sin Docker: el mount de `/mnt/extra-addons` es read-only adentro del contenedor, pero eso nunca frenó al host, y la plantilla no depende de nada que solo exista dentro de la imagen.

```
<nombre_tecnico>/
├── __init__.py             # from . import models
├── __manifest__.py
├── models/__init__.py      # vacío hasta que haya un modelo real
├── views/                  # vacío hasta la primera vista
├── security/ir.model.access.csv   # solo el header, sin filas hasta que exista un modelo
└── data/                   # vacío hasta el primer dato
```

Deliberadamente sin `controllers/` ni `demo/` — se agregan cuando el módulo los necesita, no antes — y sin modelo de ejemplo: arrancar de un `models/__init__.py` vacío evita limpiar después un modelo mal nombrado.

`__manifest__.py` con datos reales, no placeholders:

```python
{
    'name': "<Nombre legible>",
    'summary': "<una línea real>",
    'author': "<tu organización>",
    'category': '<categoría>',
    'version': '1.0.0',
    'license': 'LGPL-3',
    'depends': ['base'],   # lo que corresponda — sin adivinar
    'data': [
        # 'security/ir.model.access.csv',
    ],
}
```

```bash
make odoo-install MODULES=<nombre_tecnico>
```

### Verificación

```bash
make odoo-modules   # <nombre_tecnico> aparece instalado
make addons         # el repo está en feat/<nombre-del-modulo>, limpio
```

De acá en más, cualquier cambio a este módulo —incluida la primera vez que se instala en staging o en producción— sigue [Actualizar](#actualizar) más abajo.

---

## Actualizar

Ya tenés un módulo declarado —propio o dentro de un fork— y necesitás cambiarle código, vista o dato. Cubre también la primera vez que ese módulo se instala en un entorno donde nunca corrió: el procedimiento es idéntico, solo cambia el último comando (`odoo-install` en vez de `odoo-update`).

### Comandos

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

### Verificación

```bash
make addons          # limpio, en la rama esperada, en cada checkout
make odoo-modules    # en producción, versión nueva o módulo recién instalado
make verify
```

**Nota — qué corre en cada lado.** El servidor nunca hace `commit`/`merge`/`push`: solo `fetch`/`reset --hard`/`merge --ff-only` vía `addons-sync`, y `-i`/`-u` vía los `make` targets. Todo commit, merge y push pasa por tu máquina. Es deliberado: nada en el disco del servidor es irrecuperable — perder `addons/` entero se arregla con `make addons-sync`.

`make odoo-install`/`odoo-update` **detienen el servicio** mientras corren: es un paso explícito del operador, nunca algo que dispare el arranque del contenedor. Si el paso falla, el servicio se levanta igual y el comando reporta el error.

---

## Eliminar

El módulo ya no cumple una función — se reemplazó, se dio de baja el proceso que cubría, o nunca pasó de una prueba en desarrollo y no vale la pena mantenerlo.

**Objetivo** — el módulo desinstalado de cada base donde corría, y su código fuera del repo, integrado por el mismo camino que cualquier otro cambio.

**A mano.** Desinstalar antes de sacar el código, no después: al revés que instalar, borrar el directorio de un módulo que sigue `installed` en `ir_module_module` deja un registro apuntando a nada, y el próximo arranque o `-u` falla. Desinstalá desde Ajustes → Aplicaciones en cada entorno, en el mismo orden en que vas a promover el cambio.

### Comandos

El código viaja por el mismo camino de integración que [Actualizar](#actualizar) —rama de staging descartable, promoción a tu rama base, `addons-sync` en cada entorno— con dos diferencias: desinstalás el módulo en cada entorno *antes* de sincronizar ahí, no instalás ni actualizás después; y el cambio de código es un `git rm`, no una edición.

```bash
cd addons/<categoría>/<repo>
git checkout -b feat/eliminar-<nombre-del-modulo>
git rm -r <nombre_tecnico>
```

Seguí con la integración a staging y producción tal cual [Actualizar](#actualizar). En cada entorno, desinstalá el módulo antes de correr `addons-sync` ahí — sin `make odoo-install`/`odoo-update` al final: el módulo ya no está para instalar ni actualizar, `addons-sync` simplemente lo saca del árbol.

### Verificación

```bash
make odoo-modules   # ya no aparece
make addons         # limpio, en la rama esperada, en cada checkout
```
