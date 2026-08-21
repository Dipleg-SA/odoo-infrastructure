# odoo-infrastructure

Infraestructura Docker autoalojada para una instancia de Odoo, operada por una sola persona sobre un único servidor.

Once servicios en ocho módulos de Compose, uno por capa: reverse proxy con TLS propio, túnel de ingreso sin puertos abiertos, acceso por red local, Postgres con pooling, la aplicación, backups con recuperación a un punto en el tiempo, y observabilidad con alerting.

## Qué levanta

| Capa | Servicios | Módulo |
|---|---|---|
| DNS local | `dnsmasq` | `docker/compose.dns.yaml` |
| Proxy | `nginx` | `docker/compose.proxy.yaml` |
| Borde | `cloudflared` · `certbot` | `docker/compose.edge.yaml` |
| Datos | `postgres` · `pgbouncer` | `docker/compose.db.yaml` |
| Aplicación | `odoo` | `docker/compose.odoo.yaml` |
| Protección | `backup` (restic) + pgBackRest embebido en Postgres | `docker/compose.backups.yaml` |
| Restore | `restore-db` · `restore-files`, bajo `profiles` | `docker/compose.restore.yaml` |
| Observación | `prometheus` · `loki` · `grafana` · `alloy` | `docker/compose.observability.yaml` |

`docker/compose.yaml` no es monolítico: declara las redes y los secretos compartidos y suma un módulo por capa con `include:`. Tampoco declara el nombre del stack — eso vive en `.env`, junto a `COMPOSE_FILE`, que es lo que elige qué capas se levantan.

## Empezar

```bash
cp .env.prod.example .env   # o .env.stag.example / .env.dev.example
make secrets-init
```

El recorrido completo —qué cuentas hacen falta, en qué orden se levanta cada capa y cómo se verifica— está en [`docs/runbooks/entorno/levantar-produccion.md`](docs/runbooks/entorno/levantar-produccion.md). Ocho fases, cada una con su verificación ejecutable.

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
