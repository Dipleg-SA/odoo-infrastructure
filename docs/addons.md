# Gestión de addons

Cómo llega un módulo a producción, y qué comando corre dónde. El diseño de fondo —por qué bind-mount, por qué dos ramas fijas, por qué el servidor nunca escribe— está en [`architecture.md`](architecture.md); acá está el procedimiento.

En lo que sigue, `<rama>` es la rama de producción de cada repositorio de módulo. Sale de `ADDONS_BRANCH` en `.env`, y su default es la versión del tag `FROM odoo:` del Dockerfile — el único lugar donde vive la versión de Odoo. Staging usa siempre `<rama>-stag`.

## Un árbol por checkout

Cada entorno es un checkout propio del repositorio, con su `.env`, y **un solo árbol de addons** en `addons/<categoría>/<repo>`. Qué rama se materializa lo dice `ADDONS_BRANCH`; no hay subdirectorio por entorno, porque el directorio del checkout ya separa lo que ese nivel separaba.

| Checkout | Dónde vive | `ADDONS_BRANCH` | Quién lo actualiza |
|---|---|---|---|
| development | Solo tu máquina, uno por feature | `<rama>` | Vos. `addons-sync` lo salta apenas HEAD está en una `feat/*` |
| staging | Servidor | `<rama>-stag` | `addons-sync` |
| production | Servidor | `<rama>` (default) | `addons-sync` |

`addons-sync` **solo actualiza si el worktree está parado en la rama declarada**. Es la regla que reemplaza al viejo árbol de desarrollo opt-in: en cuanto hacés `checkout -b feat/algo`, el script avisa y no toca nada. Es el único árbol con trabajo sin commitear, y un merge lo destruiría.

## El ciclo

```
feat/*  →  <rama>-stag  →  validar en staging  →  <rama>  →  addons-sync en el servidor
```

**1. Desarrollo.** En tu checkout de development, dentro del worktree del módulo:

```bash
cd addons/<categoría>/<repo>
git checkout -b feat/nombre-del-cambio
```

Desde acá `addons-sync` deja de tocar ese repositorio, y lo dice cada vez que corre.

**2. Integración.** Cuando el cambio está listo, subilo a la rama de staging:

```bash
git checkout <rama>-stag
git reset --hard <rama>          # staging arranca siendo un clon de producción
git merge feat/nombre-del-cambio
git push --force origin <rama>-stag
```

El `reset --hard` no es opcional: la rama de staging es **descartable en todo momento** — nunca contiene nada que no exista además en una `feat/*` o en producción. Es lo que permite serializar features sin cherry-picks: si mergeaste dos cosas y solo una está lista, reseteás, mergeás solo esa, y la otra sigue esperando en su rama.

**3. Traer el cambio al servidor** y validarlo, desde el checkout de staging:

```bash
make addons-sync
```

El servidor **nunca** mergea ni pushea: solo trae. Todo lo que hay en ese árbol existe también en el remoto.

Como la rama de staging se reescribe con `--force`, el `merge --ff-only` de `addons-sync` no va a avanzar en línea recta. El script **no resuelve eso solo** —no puede saber si la rama de este checkout es descartable— y en cambio nombra el comando exacto:

```bash
git -C addons/<categoría>/<repo> reset --hard origin/<rama>-stag
```

En un checkout de staging ese reset es inofensivo; en producción, la misma condición significa que alguien commiteó en el servidor, y ahí el reset se comería trabajo. Por eso lo decide el operador y no el script.

**4. Promover.** De vuelta en tu checkout de development:

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
| `make addons` | Rama declarada del checkout, y una fila por repositorio: categoría, nombre, rama, commit corto, limpio o sucio. Funciona con el stack abajo |
| `make odoo-install MODULES=x` | Instala el módulo `x` en la base y deja el servicio arriba |
| `make odoo-update MODULES=x` | Actualiza el módulo `x` — un solo camino para cualquier tipo de cambio: código, vistas o datos |
| `make odoo-modules` | Lista los módulos instalados y su versión, leídos de la base, que es la fuente de verdad |

Instalar y actualizar **detienen el servicio** mientras corren: es un paso explícito del operador, nunca algo que dispare el arranque del contenedor. Si el paso falla, el servicio se levanta igual y el comando reporta el error — no te deja producción abajo.

## Sumar un módulo

1. Agregá una línea al manifiesto `config/odoo/addons.txt`: URL del repositorio y categoría (`custom-addons`, `oca`, `third-party` o `enterprise`).
2. `make addons-sync` — crea el clon bare y el worktree.
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
