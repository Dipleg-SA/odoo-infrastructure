# odoo-infrastructure

Infraestructura Docker autoalojada para una instancia de Odoo, operada por una sola persona sobre un único servidor.

Once servicios bajo `docker/`, una carpeta por capa y un `compose.yaml` por servicio dentro: reverse proxy con TLS propio, túnel de ingreso sin puertos abiertos, acceso por red local, Postgres con pooling, la aplicación, backups con recuperación a un punto en el tiempo, y observabilidad con alerting.

## Qué levanta

| Capa | Servicios | Carpeta |
|---|---|---|
| DNS local | `dnsmasq` | `docker/edge/dnsmasq/` |
| Proxy | `nginx` | `docker/edge/nginx/` |
| Borde | `cloudflared` · `certbot` | `docker/edge/{cloudflared,certbot}/` |
| Datos | `postgres` · `pgbouncer` | `docker/db/{postgres,pgbouncer}/` |
| Aplicación | `odoo` | `docker/app/odoo/` |
| Protección | `backup` (restic) + pgBackRest embebido en Postgres | `docker/backups/backup/` |
| Restore | `restore-db` · `restore-files`, bajo `profiles` | `docker/backups/{restore-db,restore-files}/` |
| Observación | `prometheus` · `loki` · `grafana` · `alloy` | `docker/observability/{prometheus,loki,grafana,alloy}/` |

`docker/compose.yaml` no es monolítico: declara las redes y los secretos compartidos y suma el `compose.yaml` de cada servicio con `include:`. Tampoco declara el nombre del stack — eso vive en `.env`, junto a `COMPOSE_FILE`, que es lo que elige qué capas se levantan.

## Empezar

```bash
cp .env.prod.example .env   # o .env.stag.example / .env.dev.example
make secrets-init
```

El recorrido completo —qué cuentas hacen falta, en qué orden se levanta cada capa y cómo se verifica— está en [`docs/runbooks/entorno/levantar-produccion.md`](docs/runbooks/entorno/levantar-produccion.md). Nueve bloques, cada uno con su verificación ejecutable, iguales en los tres entornos.

```bash
make verify     # en qué estado está el servidor
make up         # levantar todo
```

## Documentación

| Documento | Responde |
|---|---|
| [`PRINCIPLES.md`](PRINCIPLES.md) | ¿Qué reglas sigue este stack, y por qué? |
| [`docs/architecture.md`](docs/architecture.md) | ¿Por qué esta herramienta y no otra? |
| [`docs/stacks.md`](docs/stacks.md) | ¿Qué comparte cada entorno, y qué se decidió para staging/development? |
| [`docs/roadmap.md`](docs/roadmap.md) | ¿Cómo se llegó hasta acá, por etapas? |
| [`docs/runbooks/entorno/`](docs/runbooks/entorno/) | ¿Cómo levanto producción, staging o desarrollo? |
| [`docs/runbooks/modulos/`](docs/runbooks/modulos/) | ¿Cómo creo o modifico un módulo? |
| [`docs/runbooks/validacion/`](docs/runbooks/validacion/) | ¿Cómo confirmo que un cambio anduvo? |
| [`docs/runbooks/backup-restore/`](docs/runbooks/backup-restore/) | ¿Cómo hago o recupero un backup? |
| [`docs/runbooks/operacion/`](docs/runbooks/operacion/) | ¿Cómo opero una capa del stack en el día a día? |
| [`docs/runbooks/credenciales/`](docs/runbooks/credenciales/) | ¿Cómo roto una credencial? |
| [`docs/runbooks/troubleshooting/`](docs/runbooks/troubleshooting/) | Se rompió algo, ¿qué hago? |

## Cómo está pensado

Tres ideas gobiernan el resto y explican casi todas las decisiones:

**El bind define el acceso, no el firewall.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall, así que un `deny` no alcanza a un puerto publicado por un contenedor. Cada servicio elige uno de cuatro niveles de exposición y ninguno usa `0.0.0.0`.

**Los secretos son archivos, no variables de entorno.** Una env var queda visible en `docker inspect` y en `docker exec … env`. El mecanismo nativo de `secrets:` de Compose evita ambos sin sumar ninguna dependencia.

**Nada se actualiza solo.** Sin auto-update de imágenes, sin instalación de módulos atada al arranque. Cada cambio de versión es un acto deliberado, y las verificaciones viven en `scripts/verify.sh` para poder comprobarlo en cualquier momento.
