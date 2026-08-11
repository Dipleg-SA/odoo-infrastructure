# Gestión de addons

Cómo llega un módulo de Odoo a producción, y qué comando corre dónde. El diseño de fondo (por qué bind-mount, por qué dos ramas, por qué el servidor nunca escribe) está en `docs/architecture.md`; acá está el procedimiento.

## El ciclo

```
feat/*  →  19.0-stag  →  validar en staging  →  19.0  →  make addons-sync en el servidor
```

1. **Desarrollo.** El código nace en el [repositorio de desarrollo](#repositorio-de-desarrollo), en una rama `feat/*`, propia por cambio.
2. **Integración.** En tu Mac, dentro del clon del módulo:

   ```bash
   git checkout 19.0-stag
   git reset --hard 19.0          # staging arranca siendo un clon de producción
   git merge feat/nombre-del-cambio
   git push --force origin 19.0-stag
   ```

   El `reset --hard` no es opcional: `19.0-stag` es **descartable en todo momento** — nunca contiene nada que no exista además en una `feat/*` o en `19.0`. Es lo que permite serializar features sin cherry-picks: si mergeaste dos cosas y solo una está lista, reseteás, mergeás solo esa, y la otra sigue esperando en su rama.

3. **Traer el cambio al servidor.**

   ```bash
   make addons-sync
   docker compose -p odoo-stag up -d --force-recreate odoo   # cuando exista el stack de staging
   ```

   El servidor **nunca** mergea ni pushea — solo `fetch` + `reset --hard origin/19.0-stag`. Todo lo que hay en ese árbol existe también en GitHub.

4. **Validar** en staging.
5. **Promover.** De vuelta en tu Mac:

   ```bash
   git checkout 19.0
   git merge feat/nombre-del-cambio
   git push origin 19.0
   ```

   Esto sube **exactamente** lo que validaste — no lo que haya acumulado `19.0-stag`, que puede tener otras features de paso.

6. **Aplicar en producción:**

   ```bash
   make addons-sync
   make odoo-update MODULES=nombre_del_modulo
   ```

## Qué corre en tu Mac, qué corre en el servidor

| | Tu Mac | Servidor |
|---|---|---|
| `commit` / `merge` / `push` | Sí — todos | Nunca |
| `fetch` / `reset --hard` / `pull` | — | Sí — `make addons-sync` |
| `-i` / `-u` sobre la base | — | Sí — `make odoo-install` / `make odoo-update` |

Es deliberado: si el servidor nunca escribe en un repo de addons, nada de lo que hay en su disco es irrecuperable. Perder `addons/` completo se arregla con `make addons-sync`.

## Comandos

| Comando | Qué hace |
|---|---|
| `make addons-sync` | Clona lo que falte y actualiza los dos árboles (`addons/production/`, `addons/staging/`) desde `config/odoo/addons.txt`. Idempotente, puro host, sin contenedores |
| `make addons` | Tabla de estado: entorno, categoría, repo, rama, commit corto, sucio/limpio. También funciona con el stack abajo |
| `make odoo-install MODULES=x` | Instala el módulo `x` (`-i x --stop-after-init`) y deja el servicio arriba |
| `make odoo-update MODULES=x` | Actualiza el módulo `x` (`-u x --stop-after-init`) y deja el servicio arriba — un solo camino para cualquier tipo de cambio (código, vistas, datos), sin que haya que clasificar qué se tocó |
| `make odoo-modules` | Lista los módulos instalados y su versión, leída de `ir_module_module` — es la fuente de verdad, no hay una lista paralela versionada |

Instalar/actualizar detiene el servicio mientras corre (`stop` → `run --rm --name odoo-oneoff` → `up -d`): es un paso explícito del operador, nunca algo que dispare el arranque normal del contenedor. Un `-u` de varios minutos repitiéndose en cada restart tras un crash sería peor que la caída misma.

## Sumar un módulo nuevo

1. Agregar una línea a `config/odoo/addons.txt`: URL del repo (en tu organización) + categoría (`custom-addons`, `oca`, `third-party`, `enterprise`).
2. `make addons-sync` — crea el clon bare y los dos worktrees.
3. Si trae `external_dependencies` de Python (ej. `fs_attachment_s3` necesita `s3fs`/`boto3`), sumarlas a `docker/odoo/requirements.txt` y `docker compose build odoo`.
4. `make odoo-install MODULES=<módulo>` cuando corresponda instalarlo.

Los módulos de OCA se forkean primero a tu organización (públicos, por la licencia AGPL-3) con `upstream` apuntando al repo original — no se agrega `OCA/<repo>` directo al manifiesto.

## Actualizar un módulo de OCA (`upstream`)

El clon bare de un fork de OCA lleva un segundo remote:

```bash
git -C addons/.repos/<repo>.git remote add upstream https://github.com/OCA/<repo>.git
git -C addons/.repos/<repo>.git fetch upstream
```

Para traer una versión nueva, el bump se integra igual que cualquier otro cambio: en `19.0-stag` primero (`git merge upstream/19.0`), se valida en staging, y recién entonces se mergea a `19.0`. `upstream` nunca se toca en el servidor — el `fetch upstream` corre en tu Mac, junto con el resto de la integración.

## Enterprise (mayo 2027)

Es la única excepción a este modelo: la licencia OEEL prohíbe redistribuir, así que `odoo/enterprise` **no se forkea** y no tiene `19.0-stag`. Detalle completo en el backlog.

## Repositorio de desarrollo

El desarrollo de módulos (donde nacen las ramas `feat/*`) vive en un repositorio separado de este — más simple, sin la infraestructura de Docker. Este repo no versiona su código ni su configuración; solo consume lo que ese repositorio publica en tu organización.
