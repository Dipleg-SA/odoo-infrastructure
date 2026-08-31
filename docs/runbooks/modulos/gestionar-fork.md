# Gestionar fork

## Cuándo se usa

Tres momentos del mismo repositorio: **crearlo** (vas a incorporar un módulo cuyo código no arranca de un `make odoo-install` sobre algo que ya existe en el árbol), **actualizarlo** (salió una versión nueva del original y la querés traer a tu fork) o **eliminarlo** (ya no lo usás y querés sacarlo del árbol). Los tres comparten el mismo modelo: un repositorio declarado en `addons/addons.txt`, del que el checkout es dueño de su propia copia.

Crear aplica a dos orígenes distintos, con el mismo procedimiento salvo por el primer paso:

- **Origen propio** — una idea tuya, el repositorio nace vacío en tu organización.
- **Origen de terceros** (OCA, un proveedor) — el código ya existe en otro lado y su licencia permite forkear.

No aplica a módulos de Odoo Enterprise sin acceso al repositorio privado — ver [crear-enterprise](crear-enterprise.md), que no usa git en absoluto.

## Objetivo

Un repositorio declarado en el manifiesto de este checkout, con su worktree sincronizado — listo para que [gestionar-modulo](gestionar-modulo.md) trabaje adentro —, al día con su origen cuando corresponde, y fuera del árbol sin dejar restos cuando deja de usarse.

---

## Crear

**A mano.** **Origen propio:** creá el repositorio vacío en tu organización, con al menos la rama de versión que usa este stack (`ADDONS_BRANCH` en `.env`; su default es la versión del tag `FROM odoo:` del Dockerfile).

**Origen de terceros:** forkealo a tu organización, en tu proveedor git. No se agrega el repositorio ajeno directo al manifiesto: sin fork no se puede parchear un módulo sin salirse del modelo, y sin un remote propio no hay dónde pushear la integración a staging.

### Comandos

```bash
# origen propio
echo "<url-de-tu-repo> custom-addons" >> addons/addons.txt
```

```bash
# origen de terceros (categoría "oca" o "third-party" según corresponda)
echo "<url-de-tu-fork> oca" >> addons/addons.txt
```

```bash
make addons-sync
```

En un checkout de desarrollo, si `ADDONS_BRANCH` es una rama de feature que todavía no existe en este repo nuevo, `addons-sync` falla al armar el worktree — creala primero con `make addons-branch` (ver [levantar-desarrollo § 5](../entorno/levantar-desarrollo.md)).

Solo si el origen es de terceros, para poder traer versiones nuevas del original más adelante (ver [Actualizar](#actualizar) más abajo):

```bash
git -C addons/.repos/<repo>.git remote add upstream <url-del-original>
git -C addons/.repos/<repo>.git fetch upstream
```

### Verificación

```bash
make addons
```

Tiene que mostrar el repositorio, limpio, en la rama declarada. Si es de terceros:

```bash
git -C addons/.repos/<repo>.git remote -v
```

Tiene que listar `upstream` además de `origin`.

---

## Actualizar

Requiere haber trackeado `upstream` al crear el fork (ver [Crear](#crear) más arriba).

### Comandos

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

### Verificación

```bash
make addons          # limpio, en la rama esperada, en cada checkout
make odoo-modules    # en producción, muestra la versión nueva
make verify
```

---

## Eliminar

**Objetivo** — el repo fuera de `addons/addons.txt`, su worktree y su clon bare borrados, y —si el módulo estaba instalado— desinstalado de la base antes de tocar el código.

### A mano

Si el módulo está instalado en alguna base, desinstalalo desde ahí antes de seguir (Ajustes → Aplicaciones → Desinstalar). Este repo no expone un comando CLI de desinstalación —Odoo no tiene un flag `-u`/`-i` simétrico para eso—, y dejar registros en `ir_module_module` apuntando a código que ya no existe puede romper el próximo arranque o `make odoo-update`.

### Comandos

```bash
nano addons/addons.txt   # sacar la línea del repo
```

```bash
git -C addons/.repos/<repo>.git worktree remove --force addons/<categoria>/<repo>
rm -rf addons/.repos/<repo>.git
```

Nada que reconstruir: el `addons_path` sale de un glob en runtime sobre lo que hay en disco, así que alcanza con reiniciar el contenedor para que deje de verlo.

```bash
docker compose restart odoo
```

### Verificación

```bash
make addons
```

Ya no debería listar ese repo ni marcarlo como huérfano.

---

**Nota de contexto — precedencia entre categorías.** Si dos módulos comparten nombre técnico, gana el de la categoría que va primero: `enterprise > custom-addons > oca > third-party > core de Odoo`. El `addons_path` se arma recorriendo las categorías en ese orden — vale la pena tenerlo presente al elegir el nombre técnico de un módulo nuevo. Odoo no documenta esta precedencia; el orden se apoya en la convención de los despliegues con módulos propietarios, no en una fuente normativa.
