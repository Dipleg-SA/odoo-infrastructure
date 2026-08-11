# Operación

Qué comando correr en el día a día, una vez que el stack ya está deployado. Para el deploy inicial ver [`INSTALL.md`](../INSTALL.md); para diagnosticar una falla, [`troubleshooting.md`](troubleshooting.md).

## Comandos

| Comando | Qué hace |
|---|---|
| `make config-init` | Crea `config/traefik/acme.json`, lo único de `config/` que no se versiona (estado de runtime). Idempotente. Paso 1 de un deploy nuevo |
| `make up` | `docker compose up -d` — levanta/reconcilia **todo** el stack (operación normal, post-deploy) |
| `make down` | `docker compose down` |
| `make logs` | `docker compose logs -f` |
| `make ps` | Estado de los servicios, en tabla |
| `make secrets-check` | Chequea permisos/grupo de todo lo que hay bajo `secrets/` |
| `make verify` | Verifica las seis capas y dice en qué estado está realmente el servidor. Exit `0` solo si no hay fallas |
| `make verify-<capa>` | Solo esa capa — `host`, `edge`, `db`, `odoo`, `backups`, `observability` |
| `make addons-sync` | Clona lo que falte y actualiza los dos árboles de addons desde `config/odoo/addons.txt`. Idempotente, puro host — no necesita contenedores levantados |
| `make addons` | Estado de cada worktree: entorno, categoría, repo, rama, commit corto, limpio/sucio. También funciona con el stack abajo |
| `make odoo-install MODULES=x` | Instala el módulo `x` en la base (`-i x --stop-after-init`) y deja el servicio arriba |
| `make odoo-update MODULES=x` | Actualiza el módulo `x` (`-u x --stop-after-init`) y deja el servicio arriba — un solo camino para cualquier cambio (código, vistas, datos) |
| `make odoo-modules` | Lista los módulos instalados y su versión, leídos de `ir_module_module` — la fuente de verdad, no hay lista paralela versionada |
| `make backup` | Corrida diaria: `pgbackrest check` → `backup --type=diff` → `restic backup` → `forget --prune`. Es lo que ejecuta el timer diario; a mano sirve para probar la cadena entera |
| `make backup-full` | `pgbackrest backup --type=full` — lo que ejecuta el timer mensual |
| `make backup-check` | `pgbackrest check` + `restic check`: valida que ambos repos sean alcanzables y estén sanos, sin escribir nada |
| `make restore-up` | Levanta **solo** `restore-db` y `restore-files` (perfil `restore`). No toca el resto del stack |
| `make restore-down` | Baja **solo** esos dos. Ojo: `docker compose --profile restore down` a secas bajaría el stack entero |

## Addons

Desplegar un cambio de módulo son dos pasos, iguales para cualquier tipo de cambio: `make addons-sync` seguido de `make odoo-update MODULES=<módulo>`. No hay build de imagen de por medio: los addons llegan por bind-mount, así que el rebuild solo lo dispara un cambio en `docker/odoo/requirements.txt` o en el entrypoint.

`make odoo-install`/`odoo-update` **detienen el servicio** mientras corren (`stop` → contenedor efímero → `up -d`): actualizar la base es un paso explícito del operador, nunca algo atado al arranque del contenedor. El ciclo completo (ramas, promoción, cómo sumar un módulo) está en [`addons.md`](addons.md).

## Verificación

`make verify` es el mismo mecanismo que usa el deploy ([`INSTALL.md`](../INSTALL.md)), y sirve igual en operación: contesta *qué está sano y qué no* sin que haya que acordarse de ningún comando. El comando y el valor esperado de cada chequeo viven en `scripts/verify.sh`, que es su dueño único — no hay una copia en la documentación que se pueda desincronizar.

Corre en cualquier momento y no escribe nada. Los chequeos que dependen de otro equipo (resolución desde la LAN, alcance desde fuera de la red) **no** están ahí: quedan como pasos manuales en `INSTALL.md`.

## Deploy inicial vs. operación normal

`make up` (= `docker compose up -d` sin argumentos) levanta **todo** el `include:` de `compose.yaml` de golpe. Durante el **deploy inicial** se usa en cambio `docker compose up -d <servicios>` para arrancar capa por capa y aislar cada una antes de sumar la siguiente (Compose es aditivo: cada `up -d` suma servicios sin tocar los que ya corren).

Una vez verificado todo el stack, `make up` pasa a ser el comando de **operación normal**: levanta y reconcilia el stack completo.

## Restore

El restore no tiene target de `make` propio — necesita un timestamp o snapshot según el incidente, así que no se puede empaquetar en un comando fijo. `make restore-up`/`make restore-down` solo manejan el ciclo de vida de los dos contenedores del perfil `restore`.

El procedimiento está en [`restore.md`](restore.md), con un escenario por tipo de incidente. **Ojo:** `restore-db` monta el `pgdata` de producción — en el proyecto por defecto, un `pgbackrest restore` pisa la base real. El simulacro semestral corre siempre bajo `-p simulacro`.
