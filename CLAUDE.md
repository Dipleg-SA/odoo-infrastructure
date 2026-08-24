# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Idioma

**Todo el repositorio está en español**: comentarios de código, documentación, mensajes de commit y salida de los scripts. Escribí en español, en la misma voz directa que ya usan los archivos. Los identificadores (servicios, variables, targets) quedan en inglés donde ya lo están.

El estilo de comentarios en archivos versionados de código y config es obligatorio y vive en `.claude/rules/comment-style.md`.

## Comandos

Dos verificaciones distintas, y no se reemplazan: `make test` corre sin Docker levantado ni red, sobre lo que se puede afirmar leyendo el repositorio; `make verify` dice en qué estado está un deploy real, y **eso** necesita el sistema corriendo.

`tests/` cubre el contrato de los tres entrypoints (`docker compose config`), `addons.sh` de punta a punta contra repos git de verdad, y —con los stubs de `tests/stubs/`, que registran cada invocación— los derivadores de `verify.sh`, `cert.sh`, `capa.sh`, `timers.sh` y los dos de secrets. Al tocar un script, la pregunta es si el test **falla** cuando se rompe lo que dice cubrir: mutá y comprobalo, que ya aparecieron aserciones que pasaban por el motivo equivocado.

Los targets siguen una sola filosofía, `<capa>-<verbo>`, para las cinco capas con contenedores —`edge` (dnsmasq+nginx+cloudflared+certbot), `db`, `odoo`, `backups`, `observability`—; `host` es la única sin ciclo de vida (son chequeos de SO). `scripts/capa.sh` resuelve qué servicios de cada capa trae *este* stack contra la composición real, así que un `db-up` en development (sin `backups`/`observability`) no falla por una capa ausente. `up`/`down`/`logs`/`ps` sin prefijo siguen siendo el stack completo.

```bash
make test                   # tests/, sin levantar nada (~3 s)
make verify                 # estado del servidor entero, capa por capa
make <capa>-verify          # host | edge | db | odoo | backups | observability
make <capa>-up / down / restart / logs / ps   # edge | db | odoo | backups | observability
make <capa>-nuke            # borra containers/imágenes/volúmenes DE ESA CAPA — tipear 'nuke' para confirmar
make nuke                    # ídem, todo el stack + addons/ + state/ (nunca secrets/ ni .env)
make up / down / logs / ps
make addons-sync            # rearma el árbol de addons desde addons/addons.txt
make build                  # las imágenes propias de este stack
make odoo-install MODULES=x # -i explícito; MODULES es obligatorio
make odoo-update MODULES=x  # -u explícito
make cert-issue            # emisión inicial; nginx no arranca sin el archivo
make backup / backup-full / backup-check
make stanza-init / backup-init   # una sola vez por deploy, cada repositorio
make restore-seed          # siembra un stack que NO respalda desde el repositorio del que sí
make secrets-init / secrets-perms / secrets-check
sudo make host-init / timers-install / notify-test   # lo único que se instala fuera del checkout
make monitoring-role       # el rol de solo lectura que scrapea Postgres; repetible
```

Los nueve bloques de `docs/runbooks/entorno/levantar-*.md` son los mismos en los tres entornos y se corren con estos targets: qué significa cada uno en cada stack lo resuelve `capa.sh` contra la composición, no una variante del procedimiento por entorno.

Al tocar un `docker/compose.*.yaml`, la verificación más fuerte es que **la config resuelta no cambie**:

```bash
docker compose config > /tmp/antes.yaml
# … cambio …
docker compose config | diff /tmp/antes.yaml -
```

Para scripts, `bash -n scripts/<x>.sh` y después correrlos de verdad. **Correr `make verify` encontró que la mitad de sus propios `ok` mentían** cuando los servicios estaban abajo; asumí que cualquier verificación no ejecutada puede estar mintiendo.

## Arquitectura

**Un entrypoint por entorno**, cada uno solo redes, secrets y un `include:` por capa: `docker/compose.yaml` (producción, 11 secrets), `docker/compose.staging.yaml` (8 — sin backups, sin observabilidad, sin dnsmasq) y `docker/compose.dev.yaml` (3, todos generados — solo proxy, datos y aplicación). Cuál se usa lo dice `COMPOSE_FILE` en `.env`. Los dos que no son producción sacan el correo saliente con `SMTP_HOST: ""`, para que un `.env` copiado no alcance para mandar mail real. El nombre del stack no se declara ahí: sale de `COMPOSE_PROJECT_NAME` en `.env`, y de él derivan `container_name`, volúmenes, redes y **tags de imagen**. Nunca un archivo monolítico, nunca `compose.override.yaml` — ese nombre dispara el autoload implícito de Compose.

| Capa | Servicios | Módulo |
|---|---|---|
| DNS local | `dnsmasq` | `docker/compose.dns.yaml` |
| Proxy | `nginx` | `docker/compose.proxy.yaml` |
| Borde | `cloudflared` · `certbot` | `docker/compose.edge.yaml` |
| Datos | `postgres` · `pgbouncer` | `docker/compose.db.yaml` |
| Aplicación | `odoo` | `docker/compose.odoo.yaml` |
| Protección | `backup` (restic) + pgBackRest dentro de Postgres | `docker/compose.backups.yaml` |
| Restore | `restore-db` · `restore-files`, bajo `profiles` | `docker/compose.restore.yaml` |
| Observación | `prometheus` · `loki` · `grafana` · `alloy` | `docker/compose.observability.yaml` |

Cosas que no se deducen leyendo un archivo solo:

- **pgBackRest no tiene contenedor propio**: vive dentro de la imagen de Postgres, porque `archive_command` lo ejecuta el proceso de la base.
- **`archive_mode` lo fija el `-c` de `docker/compose.db.yaml`, no `postgresql.conf`** —ese archivo es el mismo para los tres entornos—. Un stack sin la capa de backups apunta a la stanza de producción para restaurar: con el archivado prendido le empuja su propio WAL y contamina el repositorio real. `PG_ARCHIVE_MODE=off` en su `.env`, y `db-verify` espera el valor según las capas del stack.
- **`docker/odoo/entrypoint.sh` genera config en runtime**. El `addons_path` sale de un glob sobre cuatro categorías en orden de precedencia (`enterprise > custom-addons > oca > third-party`), y `admin_passwd`, SMTP y credenciales se appendean al conf. `config/odoo/odoo.conf` es solo la base.
- **PgBouncer corre en modo transacción**, lo que rompe `LISTEN/NOTIFY`. Por eso `server_wide_modules` incluye `bus_alt_connection`, que le da al bus su propia conexión directa. Sin ese módulo Odoo arranca igual y el chat en vivo deja de actualizarse.
- **Instalar o actualizar módulos nunca va atado al arranque.** Es un one-off explícito del operador contra `postgres:5432`, no contra PgBouncer.
- **`addons/` se gitignora por contenido, no entero.** Lo versionado es la plantilla `addons/addons.txt.example` y el esqueleto vacío de las cuatro categorías (`.gitkeep`). El manifiesto real, `addons/addons.txt`, es local a cada checkout —igual que `.env`, y por lo mismo: difiere de verdad entre producción, staging y development— y se bootstrapea con `cp`. Los pines Python que `pydeps-sync` deriva de esos manifiestos viven al lado y funcionan igual: `addons/requirements.txt.example` versionado, `addons/requirements.txt` local y bootstrapeado con `cp`. Son función de qué addons trae *este* deployment. Lo que `scripts/addons.sh` clona adentro de cada categoría, y los bare de `.repos/`, tampoco se versiona.

## Invariantes que viven en dos archivos

Estos valores están duplicados por necesidad —hay formatos que no interpolan variables— y `verify.sh` los cruza. Si tocás un lado, corré la capa correspondiente:

| Un lado | El otro | Qué pasa si divergen |
|---|---|---|
| categorías en `addons.sh` | bucle `for category` en `entrypoint.sh` | los módulos se clonan y nunca se cargan |
| rama de addons en `.env` | tag `FROM odoo:` del Dockerfile | ramas de una versión montadas en un Odoo de otra |
| `RESTIC_KEEP_*` | `BACKUP_RETENTION_DAYS` | un restore viejo se queda sin adjuntos |
| `RESTIC_MAX_AGE` | `OnCalendar` de `config/systemd/` | el contenedor queda unhealthy para siempre |
| GID de cada secret | usuario real del contenedor que lo lee | el consumidor no puede leerlo (ver abajo) |

## Reglas que cuestan caro de redescubrir

- **El acceso lo define el `ports:`, no el firewall.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall. Cuatro niveles, nunca `0.0.0.0`. Ese criterio **no habla de los binds internos del contenedor**: un proceso que escucha en `0.0.0.0` sin `ports:` no expone nada al host, y a veces es necesario.
- **Los secretos son archivos, nunca variables de entorno** — una env var queda visible en `docker inspect`. Compose fuera de Swarm **ignora `uid`/`gid`/`mode`** de los secrets de archivo, así que un `600` root-owned deja sin lectura a cualquier contenedor no-root. El mapa de GIDs esperados es dueño único de `scripts/secrets-perms.sh`; verificá el usuario real de la imagen, muchas corren distroless.
- **Parametrizá por `.env` solo lo que se usa dentro de un `docker/compose.*.yaml`.** Cuando el valor vive en el archivo de config propio de una herramienta, tiene que llegar por el mecanismo que *esa herramienta* ofrezca: Compose no interpola dentro de archivos bind-mounted. Loki necesita `-config.expand-env=true` **y** un bloque `environment:`, porque expande desde su propio entorno. nginx sustituye con `envsubst` sobre `/etc/nginx/templates`, y `NGINX_ENVSUBST_FILTER` acota qué variables entran — sin él, una env var homónima de una de nginx (`$host`, `$status`) se la come la sustitución.
- **Los compose viven en `docker/`, el `.env` en la raíz.** Compose lee `.env` del directorio donde se corre el comando, no del que contiene el archivo elegido, así que `COMPOSE_FILE=docker/compose.yaml` alcanza y ningún comando lleva `-f`. Dos consecuencias: toda ruta relativa de un compose sale con `../` (`../config/…`, `../secrets/…`) porque el directorio de proyecto pasa a ser `docker/`, y sin `COMPOSE_PROJECT_NAME` el fallback del nombre de proyecto es el literal `docker`, igual en toda máquina — dos checkouts sin la variable comparten volúmenes.
- **La imagen de Odoo lee sus pines de un contexto de build aparte.** `addons/requirements.txt` queda fuera del contexto (`docker/odoo`), así que llega por `additional_contexts: {addons: ../addons}` y `COPY --from=addons`. El corchete de `requirements.tx[t]` no es un typo: hace el `COPY` opcional —con cero matches, un glob normal aborta el build— para que un checkout sin pines buildee igual. El `RUN` que lo instala va condicionado con `if`, no con `&&`: un `;` ahí dejaría que un `pip install` fallado devuelva 0 y produzca una imagen sin dependencias.
- **Las units de systemd llevan el nombre del proyecto adelante**, y `scripts/timers.sh` es dueño único de ese nombre y de qué units corresponden — lo deriva de la composición (`backup` → los dos timers de backup, `certbot` → `cert-renew`), no de una lista. `verify.sh` le pregunta en vez de repetir nombres, y con eso dos checkouts en el mismo host no se pisan las units.
- **Nunca archivos `.example` paralelos** a un config: son una copia que se desincroniza. Si el valor no se puede parametrizar, se elimina o se versiona literal.
- **`scripts/verify.sh` es dueño único de qué se chequea y qué se espera.** `docs/runbooks/` nombra el comando; los valores esperados no se duplican en la documentación.
- `docker compose port` devuelve `invalid IP:0` con exit 0 para un puerto **no** publicado — no cadena vacía.
- `alloy validate` solo valida sintaxis: acepta constantes inexistentes con exit 0. Para probar que una referencia resuelve hay que ejecutar Alloy y leer su API.
- `dockerd` no arranca si `daemon.json` tiene claves desconocidas, incluidos comentarios simulados.

## Documentación: qué va dónde

| Archivo | Contenido |
|---|---|
| `PRINCIPLES.md` | las reglas del stack, en imperativo, con el mecanismo que las implementa |
| `docs/architecture.md` | por qué esta herramienta y no otra, y qué se descartó |
| `docs/stacks.md` | qué comparte cada entorno y las decisiones tomadas para staging y development |
| `docs/roadmap.md` | plan de implementación por etapas |
| `docs/runbooks/` | manual de procedimientos: un archivo por procedimiento, genérico. Dos plantillas — Cuándo se usa · Objetivo · A mano · Comandos · Verificación para lo deliberado; Síntoma · Diagnóstico · Fix para troubleshooting. Subcarpetas: `entorno/` · `modulos/` · `validacion/` · `backup-restore/` · `operacion/` · `credenciales/` · `troubleshooting/{host,edge,datos,odoo,backups-y-dr,observability}/` |

El contexto histórico, los incidentes y las justificaciones largas van a `docs/`, **nunca inline** en el código.

## De dónde viene este repositorio

Este es el **producto**: la versión genérica y agnóstica del stack, con historia propia —raíz propia, sin ancestro común— y sin rastros de ningún deployment concreto. `PRINCIPLES.md` es la fuente de las reglas y `docs/roadmap.md` el plan por etapas.

El deployment original del que salió vive en otro repositorio, con su propia historia y su `.specs/` (constitución, backlog y specs de spec-flow). **Nada de ese repositorio se trae acá**: es el que tiene la IP pública, el dominio y el hardware que esta versión elimina.

Al escribir acá, cualquier valor que solo sirva a un deployment concreto —hostnames, IPs, cantidades de RAM, fechas, nombres de proveedores como ejemplo obligatorio— es un defecto, no un detalle.
