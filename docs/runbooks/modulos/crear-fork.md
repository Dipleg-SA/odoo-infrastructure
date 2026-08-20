# Crear fork

## Cuándo se usa

Vas a incorporar un módulo cuyo código no arranca de un `make odoo-install` sobre algo que ya existe en el árbol: hace falta declarar el repositorio que lo va a contener. Aplica a dos orígenes distintos, con el mismo procedimiento salvo por el primer paso:

- **Origen propio** — una idea tuya, el repositorio nace vacío en tu organización.
- **Origen de terceros** (OCA, un proveedor) — el código ya existe en otro lado y su licencia permite forkear.

No aplica a módulos de Odoo Enterprise sin acceso al repositorio privado — ver [crear-enterprise](crear-enterprise.md), que no usa git en absoluto.

## Objetivo

Un repositorio declarado en el manifiesto de este checkout, con su worktree sincronizado — listo para que [crear-modulo](crear-modulo.md) o [actualizar-modulo](actualizar-modulo.md) trabajen adentro.

## A mano

**Origen propio.** Creá el repositorio vacío en tu organización, con al menos la rama de versión que usa este stack (`ADDONS_BRANCH` en `.env`; su default es la versión del tag `FROM odoo:` del Dockerfile).

**Origen de terceros.** Forkealo a tu organización, en tu proveedor git. No se agrega el repositorio ajeno directo al manifiesto: sin fork no se puede parchear un módulo sin salirse del modelo, y sin un remote propio no hay dónde pushear la integración a staging.

## Comandos

```bash
# origen propio
echo "<url-de-tu-repo> custom-addons" >> addons/addons.txt

# origen de terceros (categoría "oca" o "third-party" según corresponda)
echo "<url-de-tu-fork> oca" >> addons/addons.txt

make addons-sync
```

Solo si el origen es de terceros, para poder traer versiones nuevas del original más adelante ([actualizar-fork](actualizar-fork.md)):

```bash
git -C addons/.repos/<repo>.git remote add upstream <url-del-original>
git -C addons/.repos/<repo>.git fetch upstream
```

## Verificación

```bash
make addons
```

Tiene que mostrar el repositorio, limpio, en la rama declarada. Si es de terceros:

```bash
git -C addons/.repos/<repo>.git remote -v
```

Tiene que listar `upstream` además de `origin`.

---

**Nota de contexto — precedencia entre categorías.** Si dos módulos comparten nombre técnico, gana el de la categoría que va primero: `enterprise > custom-addons > oca > third-party > core de Odoo`. El `addons_path` se arma recorriendo las categorías en ese orden — vale la pena tenerlo presente al elegir el nombre técnico de un módulo nuevo. Odoo no documenta esta precedencia; el orden se apoya en la convención de los despliegues con módulos propietarios, no en una fuente normativa.
