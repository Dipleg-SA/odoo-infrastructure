# Roadmap de implementación

Plan para llevar el repositorio del estado actual —un solo stack, con Traefik en el borde— al que describe la Parte II de [stacks.md](stacks.md): tres entornos, nginx, un árbol de addons por checkout.

El principio de ordenamiento es uno solo: **producción está corriendo y no se toca hasta que lo nuevo esté probado en otro lado.** De ahí sale la inversión más importante del plan — staging se construye **antes** de migrar producción a nginx, y sirve de ensayo del cutover.

## Dos decisiones ya tomadas

**El nombre del stack se declara en `.env`, al lado de `COMPOSE_FILE`. Sin excepciones.** Ningún `compose.*.yaml` declara `name:`: la identidad de un stack sale del mismo archivo que dice qué capas incluye, en los tres entornos y con un solo mecanismo que aprender.

```
/srv/odoo-production            COMPOSE_PROJECT_NAME=production
/srv/odoo-staging               COMPOSE_PROJECT_NAME=staging
~/odoo-development-sale         COMPOSE_PROJECT_NAME=development-sale
~/odoo-development-accountant   COMPOSE_PROJECT_NAME=development-accountant
```

El modo de falla está medido y es benigno: si la variable falta o queda vacía, Compose cae al **nombre del directorio**, que ya es único por checkout. Olvidarla no produce un volumen compartido, produce un nombre más feo. El único caso peligroso es copiar un `.env` de un checkout a otro, y contra eso no hay mecanismo que ayude.

Se descartó declarar `name:` en cada entrypoint. Con un literal compartido entre dos checkouts de development, los dos resuelven al **mismo** volumen `development_pgdata`: no colisionan al arrancar, porque corre uno a la vez, se pisan los datos en silencio.

Renombrar el proyecto de producción **renombra sus volúmenes**, y Docker no sabe renombrar un volumen: hay que crear el nuevo y copiar, con el stack abajo. Si la adopción de esta rama en el servidor pasa por un redeploy con restore —que es lo esperable, porque cambia el borde entero—, los volúmenes nacen con el nombre nuevo y no hay migración. Si se quiere renombrar antes, sobre el stack actual, se copian `pgdata` y `odoo-data`; `prometheus-data`, `loki-data` y `grafana-data` se dejan nacer vacíos, porque son datos de diagnóstico y no de restauración.

**La alerta de vencimiento de certificado pasa a `state/textfile/`.** Hoy sale de `traefik_tls_certs_not_after` y con certbot se queda sin fuente. `cert-renew.sh` escribe la métrica por el mismo mecanismo que ya usa `backup.sh`, sin sumar componentes. La salvedad: mide lo que certbot cree, no lo que nginx sirve — el caso «se renovó pero nginx no recargó» queda fuera y necesitaría un chequeo sobre el puerto.

---

## Etapa 0 — El agujero de hoy

Lo único de todo el plan que arregla algo que ya está roto. No depende de ninguna otra etapa.

La resiliencia ante caída de internet depende de que los equipos de la LAN usen dnsmasq como resolver, y eso lo decide el DHCP del router. El repositorio nunca lo pide, y el chequeo que parece cubrirlo usa `dig … @servidor`: prueba que dnsmasq contesta, no que alguien le pregunte.

- `INSTALL.md`: prerrequisito de apuntar el DNS de la LAN al servidor.
- El chequeo de la fase de borde pasa a `dig +short` **sin** `@`, corrido desde un equipo de la LAN.
- `verify.sh`: dejar dicho que `sano dnsmasq` valida que responde, no que se lo consulte. Desde el servidor no se puede verificar lo otro.

**Verificación.** Desde un equipo de la LAN, `dig +short <hostname>` a secas devuelve la IP local del servidor.

## Etapa 1 — Refactors mecánicos, producción idéntica

Cuatro cambios independientes entre sí. Ninguno cambia lo que corre.

- `ADDONS_BRANCH` reemplaza a `ODOO_BRANCH`; default leído del `FROM` del Dockerfile; el chequeo de `verify.sh` pasa de igualdad a prefijo.
- `addons.sh` a un árbol por checkout: se van `entornos()`, `ensure_dev_worktree()` y el bootstrap de la rama `-stag`.
- Dos guardas en el `Makefile`: `require-backups` sobre `backup`, `backup-full` y `backup-check`; `require-restore` sobre `restore-up` y `restore-down`. Son capas distintas — staging **sí** lleva restore —, así que una sola guarda le prohibiría a staging justo lo que tiene que hacer.
- Extraer `compose.dns.yaml` de `compose.edge.yaml`, y `compose.restore.yaml` de `compose.backups.yaml`.

**Verificación.** Es la que hace segura toda la etapa: la config resuelta tiene que ser idéntica antes y después.

```bash
docker compose config > /tmp/antes.yaml
# … refactor …
docker compose config | diff /tmp/antes.yaml -
```

Si no cambió la config resuelta, producción no puede haber cambiado.

**Migración.** El árbol de addons del checkout de producción sube un nivel: `addons/production/<categoría>/` pasa a `addons/<categoría>/`. Los worktrees se rehacen con `addons.sh`, no se mueven a mano — pero primero hay que borrar los árboles viejos (`rm -rf addons/production addons/staging addons/development`), porque sus worktrees retienen la rama y `worktree add` fallaría con `already checked out`. `addons.sh sync` aborta con ese mensaje si todavía están.

## Etapa 2 — Nombre de proyecto e imágenes

- `name: infrastructure-odoo` **sale de `compose.yaml`** y no se reemplaza: el nombre pasa a vivir en `.env`, como en los otros dos entornos.
- `.env.example` gana `COMPOSE_PROJECT_NAME` y `COMPOSE_FILE`, juntos y arriba: son los dos valores que definen qué stack es este checkout.
- Tags `local/<servicio>:${COMPOSE_PROJECT_NAME}` en `compose.db.yaml`, `compose.odoo.yaml`, `compose.dns.yaml` y en `restore-db`.
- `verify.sh` chequea que `COMPOSE_PROJECT_NAME` esté declarado en `.env`. No es fatal que falte —Compose cae al nombre del directorio— pero un stack cuyo nombre depende de dónde se clonó es un stack que no sabés cómo se llama hasta correrlo.

**Verificación.** `docker compose config` muestra los tags nuevos y el proyecto nuevo.

**Cuidado.** Es la primera etapa que **no** es transparente para un stack corriendo: renombrar el proyecto renombra los volúmenes, así que `up -d` después de esto arranca con `pgdata` vacío. En un servidor ya desplegado, va junto con la migración de volúmenes o junto al redeploy; en un deploy nuevo no cuesta nada.

El renombre también alcanza al `hostname` de `backup`, y ahí no hay migración posible: restic agrupa la retención por `(host, paths)`, así que los snapshots viejos quedan en un grupo propio al que no le entra nada nuevo. Como `--keep-*` retiene por cantidad y no por edad, ese grupo **nunca se purga**: se paga en R2 para siempre y un `restic snapshots` muestra dos linajes. Si no se los quiere conservar, se borran a mano con `restic forget --host <nombre viejo>` después del primer backup exitoso con el nombre nuevo.

## Etapa 3 — nginx reemplaza a Traefik

Traefik **sale del repositorio** en esta etapa: no hay convivencia ni archivo transitorio. El reverse proxy pasa a ser nginx, uno por entorno, y `config/traefik/` se borra en el mismo commit.

Lo que protege a producción no es un archivo paralelo, es su checkout: se clona **fijado al último tag, con `HEAD` detached**, justamente como guard-rail. Mientras nadie haga `git checkout` de un tag nuevo en `/srv/odoo-production`, ese stack sigue corriendo Traefik aunque la rama ya no lo tenga. Es el mismo criterio de «nunca `:latest`» aplicado al propio repositorio.

La capa de borde se parte en dos, porque development no lleva túnel ni certificados:

| Módulo | Servicios | Quién lo incluye |
|---|---|---|
| `compose.proxy.yaml` | `nginx` | producción, staging, development |
| `compose.edge.yaml` | `cloudflared` · `certbot` | producción, staging |

- `config/nginx/` con las plantillas `envsubst` de la imagen oficial. `config/traefik/` se borra.
- `resolver 127.0.0.11 valid=10s` y `proxy_pass` a través de una variable, desde la primera línea: sin eso nginx cachea la IP de Odoo al arrancar y devuelve 502 tras cada recreación.
- Las labels de Traefik salen de `compose.odoo.yaml`; el ruteo pasa a ser archivo, no descubrimiento.
- `scripts/cert-renew.sh` y las units `odoo-cert-renew.{service,timer}`, con el mismo `OnFailure=` que los backups. `cert-renew.sh` escribe la métrica de vencimiento en `state/textfile/`.
- `prometheus.yaml` pierde el job `traefik`. Las dos reglas de Grafana se migran: tasa de error a LogQL sobre el access log, vencimiento de certificado a la métrica de textfile.
- `scripts/config-init.sh` y su target del Makefile se borran: existían solo para pre-crear `acme.json`, y el estado de certbot vive en un volumen nombrado.
- `verify.sh`: los chequeos de borde pasan de Traefik a nginx. `INSTALL.md` fase 3, `docs/troubleshooting.md`, `docs/architecture.md`.

**Verificación.** Un stack descartable en la máquina del operador, con nombre de proyecto propio, sirviendo Odoo por nginx sin TLS. Mismo método con el que se validaron `daemon.json`, Loki y Alloy: contenedores de prueba, nunca los secrets reales.

**Producción no se entera.** Su checkout sigue en el tag anterior. La etapa termina con un tag nuevo publicado y nadie corriéndolo todavía.

## Etapa 4 — Staging en pie

El primer stack nuevo, y el primero que corre nginx de verdad: con TLS, con túnel y con tráfico. Es el ensayo del cutover de producción.

- Checkout, `.env` con `COMPOSE_PROJECT_NAME=staging` y `COMPOSE_FILE=compose.staging.yaml`, `secrets-init.sh` más los tres valores que van a mano, túnel y hostname en Cloudflare.
- `compose.staging.yaml` con su `include:` —proxy, edge, datos, aplicación, restore—, sus 8 secrets y `ports: !reset []`.
- Siembra por restore desde el repositorio remoto, que es a la vez el primer simulacro completo.
- `integrity-check.sh` adaptado para no depender del servicio `backup`.

**Verificación.** `make verify` en staging, con las capas ausentes omitidas y no en rojo. El hostname de staging sirviendo con certificado válido emitido por certbot. El chat en vivo funcionando, que es lo que prueba el `location /websocket`. Y una renovación forzada (`--force-renewal`) para ejercitar el timer y el reload de nginx antes de que producción dependa de eso.

## Etapa 5 — Cutover de producción

Ya no es un cambio de código: el código está escrito y probado desde la etapa 3. Es una **operación**, y por eso es corta.

```bash
cd /srv/odoo-production
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
docker compose up -d
```

**Rollback:** `git checkout <tag anterior> && docker compose up -d`. Vuelve `compose.edge.yaml` con Traefik y `config/traefik/` completo, y `acme.json` nunca se fue del disco porque está gitignoreado. El estado de certbot tampoco se pierde: vive en un volumen nombrado que un checkout no toca.

Esto es lo que compra fijar el checkout a un tag en vez de seguir una rama: el rollback del borde entero es un comando, y no depende de que nadie se haya acordado de no borrar un archivo.

**Verificación.** Las alertas primero. Una alerta migrada mal no falla ruidosa: no dispara nunca.

## Etapa 6 — Development

- `compose.dev.yaml`: borde, datos, aplicación. nginx sin TLS, publicando en loopback.
- `.env.example` con el caso de development: `COMPOSE_FILE`, nombre de proyecto único por checkout, `ADDONS_BRANCH`.

**Verificación.** Dos checkouts clonados, uno levantado, y comprobar que el otro tiene sus propios volúmenes — que es el modo de falla de reusar el nombre de proyecto.

## Etapa 7 — Documentación

- `INSTALL.md` fases 10 y 11, hoy esqueletos vacíos.
- `PRINCIPLES.md`: convención del árbol de addons, capa de borde, y `compose.staging.yaml`/`compose.dev.yaml` como entrypoints en vez de módulos excluidos del `include:`.
- `docs/stacks.md`: la Parte I pasa a describir el estado nuevo y la Parte II deja de ser futuro.

---

## Árbol objetivo del repositorio

```
infrastructure-odoo/
├── .claude/rules/comment-style.md
├── .env.example
├── .gitignore
├── INSTALL.md
├── Makefile
├── PRINCIPLES.md
├── README.md
│
├── compose.yaml                    entrypoint · producción
├── compose.staging.yaml            entrypoint · staging               ← nuevo
├── compose.dev.yaml                entrypoint · development           ← nuevo
│
├── compose.dns.yaml                capa · dnsmasq                     ← extraído de edge
├── compose.proxy.yaml              capa · nginx                       ← extraído de edge
├── compose.edge.yaml               capa · cloudflared + certbot
├── compose.db.yaml                 capa · postgres + pgbouncer
├── compose.odoo.yaml               capa · odoo
├── compose.backups.yaml            capa · restic
├── compose.restore.yaml            capa · restore-db + restore-files  ← extraído de backups
├── compose.observability.yaml      capa · prometheus + loki + grafana + alloy
│
├── config/
│   ├── nginx/                                                         ← reemplaza traefik/
│   │   ├── nginx.conf
│   │   └── templates/
│   │       ├── 00-upstreams.conf.template
│   │       ├── 10-odoo.conf.template
│   │       └── 20-log-format.conf.template
│   ├── certbot/cli.ini                                                ← nuevo
│   ├── odoo/{odoo.conf, addons.txt}
│   ├── postgres/postgresql.conf
│   ├── pgbouncer/pgbouncer.ini
│   ├── pgbackrest/pgbackrest.conf
│   ├── prometheus/prometheus.yaml
│   ├── loki/loki.yaml
│   ├── alloy/config.alloy
│   ├── grafana/
│   │   ├── grafana.ini
│   │   ├── dashboards/*.json
│   │   └── provisioning/{alerting,dashboards,datasources,plugins}/
│   ├── docker/daemon.json
│   └── systemd/
│       ├── odoo-backup-daily.{service,timer}
│       ├── odoo-backup-monthly.{service,timer}
│       ├── odoo-backup-notify@.service
│       └── odoo-cert-renew.{service,timer}                            ← nuevo
│
├── docker/
│   ├── dnsmasq/Dockerfile
│   ├── odoo/{Dockerfile, entrypoint.sh, requirements.txt}
│   └── postgres/Dockerfile
│
├── docs/
│   ├── addons.md · architecture.md · operations.md
│   ├── restore.md · roadmap.md · stacks.md · troubleshooting.md
│
├── scripts/
│   ├── addons.sh              más corto: sin entornos
│   ├── backup.sh
│   ├── cert-renew.sh                                                  ← nuevo
│   ├── failure-notify.sh
│   ├── integrity-check.sh     sin depender del servicio backup
│   ├── secrets-init.sh
│   ├── secrets-perms.sh
│   └── verify.sh
│       config-init.sh                                                 ← se borra
│
└── state/{meta,textfile}/.gitkeep
```

No versionado, y propio de cada checkout: `.env`, `secrets/`, `addons/<categoría>/<repo>`, `addons/.repos/*.git`, y `state/*` salvo los `.gitkeep`.

## Layout de deployment

Las dos primeras líneas del `.env` de cada checkout son las que definen el stack.

```
SERVIDOR
  /srv/odoo-production/           COMPOSE_PROJECT_NAME=production
                                  COMPOSE_FILE=compose.yaml
                                  11 secrets · systemd: backups + cert-renew

  /srv/odoo-staging/              COMPOSE_PROJECT_NAME=staging
                                  COMPOSE_FILE=compose.staging.yaml
                                  8 secrets · systemd: cert-renew

MÁQUINA DEL OPERADOR
  ~/odoo-development-sale/        COMPOSE_PROJECT_NAME=development-sale
                                  COMPOSE_FILE=compose.dev.yaml

  ~/odoo-development-accountant/  COMPOSE_PROJECT_NAME=development-accountant
                                  COMPOSE_FILE=compose.dev.yaml

                                  3 secrets, todos generados · sin systemd
```
