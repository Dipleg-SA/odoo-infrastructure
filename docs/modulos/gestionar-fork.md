# Gestionar fork

## Cuándo se usa

Tres momentos del mismo repositorio: **crearlo** (vas a incorporar un módulo cuyo código no arranca de un `make addons-install` sobre algo que ya existe en el árbol), **actualizarlo** (salió una versión nueva del original y la querés traer a tu fork) o **eliminarlo** (ya no lo usás y querés sacarlo del árbol). Los tres comparten el mismo modelo: un repositorio declarado en `addons/addons.txt`, del que el checkout es dueño de su propia copia.

Crear aplica a dos orígenes distintos, con el mismo procedimiento salvo por el primer paso:

- **Origen propio** — una idea tuya, el repositorio nace vacío en tu organización.
- **Origen de terceros** (OCA, un proveedor) — el código ya existe en otro lado y su licencia permite forkear.

No aplica a módulos de Odoo Enterprise sin acceso al repositorio privado — ver [gestionar-enterprise](gestionar-enterprise.md), que no usa git en absoluto.

## Objetivo

Un repositorio declarado en el manifiesto de este checkout, con su worktree sincronizado — listo para que [gestionar-modulo](gestionar-modulo.md) trabaje adentro —, al día con su origen cuando corresponde, y fuera del árbol sin dejar restos cuando deja de usarse.

## Flujo rápido

Este es el recorrido completo para incorporar, actualizar o retirar un repositorio de addons. Las secciones siguientes explican los comandos Git y los casos de excepción.

1. **Crear o forkear el repositorio** en tu organización y declararlo en `addons/addons.txt`. En desarrollo, si la rama de `ADDONS_BRANCH` todavía no existe en el repo nuevo:

   ```bash
   make repo-branch
   make repo-sync
   ```

2. **Desarrollar módulos dentro del worktree** con el flujo de [gestionar módulo](gestionar-modulo.md). Para cada cambio que agregue dependencias Python:

   ```bash
   make addons-deps
   make build   # solo si addons-deps agregó o cambió pines
   ```

3. **Actualizar un fork de terceros.** Traer `upstream/<rama>`, integrarlo a `<rama>-stag` con Git y validarlo en staging:

   ```bash
   make repo-sync
   make addons-deps
   make build   # solo si addons-deps agregó o cambió pines
   make addons-update MODULES=<módulos_afectados>
   make verify
   ```

4. **Promover lo validado a `<rama>`** con Git y aplicarlo en producción:

   ```bash
   make repo-sync
   make addons-deps
   make build   # solo si addons-deps agregó o cambió pines
   make addons-update MODULES=<módulos_afectados>
   make verify
   ```

5. **Retirar un repositorio.** Desinstalar antes todos sus módulos instalados en cada base y sacar su línea de `addons/addons.txt` en cada checkout. Luego, en cada entorno:

   ```bash
   make repo-status
   make verify
   ```

| Situación | Comando |
| --- | --- |
| La rama de desarrollo aún no existe en el repo nuevo | `make repo-branch` y `make repo-sync` |
| Incorporar un repo ya creado o forkeado | `make repo-sync` |
| La actualización agregó dependencias Python | `make addons-deps` y, si agregó pines, `make build` |
| Actualizar módulos ya instalados de un fork | `make addons-update MODULES=<módulos_afectados>` |
| Comprobar el árbol tras una incorporación o baja | `make repo-status` |

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

En un checkout de desarrollo, si `ADDONS_BRANCH` es una rama de feature que todavía no existe en este repo nuevo, `repo-sync` falla al armar el worktree — creala primero con `make repo-branch` (ver [levantar-desarrollo § 5](../entorno/levantar-desarrollo.md)).

```bash
make repo-branch   # solo si esa rama de feature todavía no existe
make repo-sync
```

Solo si el origen es de terceros, para poder traer versiones nuevas del original más adelante (ver [Actualizar](#actualizar) más abajo):

```bash
git -C addons/.repos/<repo>.git remote add upstream <url-del-original>
git -C addons/.repos/<repo>.git fetch upstream
```

### Verificación

```bash
make repo-status
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
make repo-sync
make addons-deps
make build   # solo si addons-deps agregó o cambió pines
make addons-update MODULES=<módulos_afectados>   # o addons-install si alguno es nuevo
make addons-modules
docker compose logs --since 5m odoo
make verify
```

Revisá los logs de la actualización y probá en la UI de staging el flujo de cada módulo afectado, contra los datos restaurados de producción. Confirmá que no salió correo real: `ODOO_DISABLE_SMTP=1` lo bloquea. Si el cambio modifica registros existentes, comprobá también la migración. No promociones hasta que estas pruebas y `make verify` estén en verde.

Si `repo-sync` avisa que el `merge --ff-only` no avanzó en línea recta (staging se reescribió con `--force`), nombra los dos comandos posibles: `git rebase origin/<rama>-stag` para integrar, o `git reset --hard origin/<rama>-stag` si los commits locales son descartables.

Probá de verdad en staging. Recién validado, promover:

```bash
git checkout <rama>
git merge upstream/<rama>   # o merge de la rama de staging, si hubo que resolver un conflicto ahí
git push origin <rama>
```

Aplicar en producción:

```bash
make repo-sync
make addons-deps
make build   # solo si addons-deps agregó o cambió pines
make addons-update MODULES=<módulos-afectados>   # o addons-install si alguno es nuevo
```

Confirmá la versión instalada y revisá los logs recientes:

```bash
make addons-modules
docker compose logs --since 10m odoo
```

Probá el flujo específico del cambio en la UI de producción con cuidado; si dispara correo, confirmá que llegó. La validación de producción es de confirmación, no de exploración. Si falla algo que pasó en staging, registrá el caso y ampliá esa prueba para la próxima actualización.

### Verificación

```bash
make repo-status      # limpio, en la rama esperada, en cada checkout
make addons-modules   # en producción, muestra la versión nueva
make verify
```

---

## Eliminar

**Objetivo** — el repo fuera de `addons/addons.txt`, su worktree y su clon bare borrados, y —si el módulo estaba instalado— desinstalado de la base antes de tocar el código.

### A mano

Si alguno de los módulos del repo está instalado en una base, desinstalalo desde ahí antes de seguir con `make addons-uninstall MODULES=<nombre_tecnico>`. El comando usa la API ORM interna de Odoo, muestra los módulos dependientes que también serán afectados y exige confirmación explícita. Dejar registros en `ir_module_module` apuntando a código que ya no existe puede romper el próximo arranque o `make addons-update`.

Repetí la desinstalación y la baja de la línea del manifiesto en desarrollo, staging y producción: `addons/addons.txt` es local a cada checkout y no se promueve por Git.

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

```bash
make repo-status
make verify
```

### Verificación

Ya no debería listar ese repo ni marcarlo como huérfano.

---

**Nota de contexto — precedencia entre categorías.** Si dos módulos comparten nombre técnico, gana el de la categoría que va primero: `enterprise > custom-addons > oca > third-party > core de Odoo`. El `addons_path` se arma recorriendo las categorías en ese orden — vale la pena tenerlo presente al elegir el nombre técnico de un módulo nuevo. Odoo no documenta esta precedencia; el orden se apoya en la convención de los despliegues con módulos propietarios, no en una fuente normativa.
