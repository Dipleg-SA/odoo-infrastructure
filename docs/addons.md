# Gestión de addons

Cómo llega un módulo a producción, y qué comando corre dónde. El diseño de fondo —por qué bind-mount, por qué dos ramas fijas, por qué el servidor nunca escribe— está en [`architecture.md`](architecture.md); acá está el procedimiento.

En lo que sigue, `<rama>` es la rama de producción de cada repositorio de módulo: sale de `ODOO_BRANCH` en `.env` y acompaña a la versión de Odoo de la imagen. Staging usa siempre `<rama>-stag`.

## Los tres entornos

| Entorno | Dónde vive | Rama | Quién lo actualiza |
|---|---|---|---|
| `development` | Solo tu máquina | detached; de ahí salen las `feat/*` | Vos. `addons-sync` **nunca** lo toca |
| `staging` | Servidor, bajo demanda | `<rama>-stag` | `addons-sync`, con `reset --hard` |
| `production` | Servidor | `<rama>` | `addons-sync`, con `merge --ff-only` |

El de desarrollo es **opt-in**: se crea solo si ponés `ADDONS_WITH_DEV=1` en tu `.env`. En el servidor no debe existir, porque ahí nada escribe en un repositorio de módulos.

Que `addons-sync` no lo toque es deliberado: es el único árbol con trabajo sin commitear, y un `reset` o un `merge` lo destruiría. Nace *detached* porque git no permite tener la misma rama checkouteada en dos worktrees a la vez.

## El ciclo

```
feat/*  →  <rama>-stag  →  validar en staging  →  <rama>  →  addons-sync en el servidor
```

**1. Desarrollo.** En tu máquina, dentro del worktree de desarrollo del módulo:

```bash
cd addons/development/<categoría>/<repo>
git checkout -b feat/nombre-del-cambio
```

**2. Integración.** Cuando el cambio está listo, subilo a la rama de staging:

```bash
git checkout <rama>-stag
git reset --hard <rama>          # staging arranca siendo un clon de producción
git merge feat/nombre-del-cambio
git push --force origin <rama>-stag
```

El `reset --hard` no es opcional: la rama de staging es **descartable en todo momento** — nunca contiene nada que no exista además en una `feat/*` o en producción. Es lo que permite serializar features sin cherry-picks: si mergeaste dos cosas y solo una está lista, reseteás, mergeás solo esa, y la otra sigue esperando en su rama.

**3. Traer el cambio al servidor** y validarlo en staging:

```bash
make addons-sync
```

El servidor **nunca** mergea ni pushea: solo trae. Todo lo que hay en ese árbol existe también en el remoto.

**4. Promover.** De vuelta en tu máquina:

```bash
git checkout <rama>
git merge feat/nombre-del-cambio
git push origin <rama>
```

Sube **exactamente** lo que validaste, no lo que haya acumulado la rama de staging.

**5. Aplicar en producción:**

```bash
make addons-sync
make odoo-update MODULES=nombre_del_modulo
```

## Qué corre en cada lado

| | Tu máquina | Servidor |
|---|---|---|
| `commit` · `merge` · `push` | Sí — todos | Nunca |
| `fetch` · `reset --hard` · `merge --ff-only` | — | Sí, vía `make addons-sync` |
| `-i` / `-u` sobre la base | — | Sí — `make odoo-install` / `make odoo-update` |

Es deliberado: si el servidor nunca escribe en un repositorio de módulos, nada de lo que hay en su disco es irrecuperable. Perder `addons/` entero se arregla con un `make addons-sync`.

## Comandos

| Comando | Qué hace |
|---|---|
| `make addons-sync` | Clona lo que falte y actualiza los árboles desde el manifiesto. Idempotente, puro host, sin contenedores. Falla si el manifiesto está vacío |
| `make addons` | Tabla de estado: entorno, categoría, repositorio, rama, commit corto, limpio o sucio. Funciona con el stack abajo |
| `make odoo-install MODULES=x` | Instala el módulo `x` en la base y deja el servicio arriba |
| `make odoo-update MODULES=x` | Actualiza el módulo `x` — un solo camino para cualquier tipo de cambio: código, vistas o datos |
| `make odoo-modules` | Lista los módulos instalados y su versión, leídos de la base, que es la fuente de verdad |

Instalar y actualizar **detienen el servicio** mientras corren: es un paso explícito del operador, nunca algo que dispare el arranque del contenedor. Si el paso falla, el servicio se levanta igual y el comando reporta el error — no te deja producción abajo.

## Sumar un módulo

1. Agregá una línea al manifiesto `config/odoo/addons.txt`: URL del repositorio y categoría (`custom-addons`, `oca`, `third-party` o `enterprise`).
2. `make addons-sync` — crea el clon bare y los worktrees.
3. Si el módulo declara dependencias de Python, sumalas a `docker/odoo/requirements.txt` y reconstruí la imagen. Es lo único, junto al entrypoint, que dispara un rebuild.
4. `make odoo-install MODULES=<módulo>` cuando corresponda instalarlo.

Los módulos de terceros se forkean primero a tu propia organización, con el original como segundo remote. No se agrega el repositorio ajeno directo al manifiesto: sin fork no se puede parchear un módulo sin salirse del modelo.

## Actualizar un módulo de terceros

El clon bare de un fork lleva un segundo remote:

```bash
git -C addons/.repos/<repo>.git remote add upstream <url-del-original>
git -C addons/.repos/<repo>.git fetch upstream
```

Traer una versión nueva se integra como cualquier otro cambio: primero a la rama de staging (`git merge upstream/<rama>`), se valida, y recién entonces se mergea a producción. `upstream` **nunca se toca en el servidor** — ese `fetch` corre en tu máquina, junto con el resto de la integración.

## Precedencia entre categorías

Si dos módulos comparten nombre técnico, gana el de la categoría que va primero:

```
enterprise  >  custom-addons  >  oca  >  third-party  >  core de Odoo
```

El entrypoint arma el `addons_path` recorriendo las categorías en ese orden. La lista vive en dos lugares —el validador del manifiesto y el glob del entrypoint— y `make verify-odoo` comprueba que coincidan: si divergen, los módulos de la categoría que falte se clonarían sin llegar a cargarse nunca.

**Advertencia:** Odoo no documenta la precedencia del `addons_path`. Este orden se apoya en la convención de los despliegues con módulos propietarios, no en una fuente normativa.

## Módulos con licencia que prohíbe redistribuir

Son la excepción al modelo. Su licencia no permite forkearlos a una organización propia, así que no tienen fork ni rama de staging: se consumen desde su origen y su categoría se puebla por otro camino.
