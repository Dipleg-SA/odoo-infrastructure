# infrastructure-odoo

Infraestructura Docker autoalojada para una instancia de Odoo, operada por una sola persona sobre un único servidor.

Once servicios en ocho módulos de Compose, uno por capa: reverse proxy con TLS propio, túnel de ingreso sin puertos abiertos, acceso por red local, Postgres con pooling, la aplicación, backups con recuperación a un punto en el tiempo, y observabilidad con alerting.

## Qué levanta

| Capa | Servicios | Módulo |
|---|---|---|
| DNS local | `dnsmasq` | `compose.dns.yaml` |
| Proxy | `nginx` | `compose.proxy.yaml` |
| Borde | `cloudflared` · `certbot` | `compose.edge.yaml` |
| Datos | `postgres` · `pgbouncer` | `compose.db.yaml` |
| Aplicación | `odoo` | `compose.odoo.yaml` |
| Protección | `backup` (restic) + pgBackRest embebido en Postgres | `compose.backups.yaml` |
| Restore | `restore-db` · `restore-files`, bajo `profiles` | `compose.restore.yaml` |
| Observación | `prometheus` · `loki` · `grafana` · `alloy` | `compose.observability.yaml` |

`compose.yaml` no es monolítico: declara las redes y los secretos compartidos y suma un módulo por capa con `include:`. Tampoco declara el nombre del stack — eso vive en `.env`, junto a `COMPOSE_FILE`, que es lo que elige qué capas se levantan.

## Empezar

```bash
cp .env.example .env
make secrets-init
```

El recorrido completo —qué cuentas hacen falta, en qué orden se levanta cada capa y cómo se verifica— está en [`INSTALL.md`](INSTALL.md). Son once fases, cada una con su verificación ejecutable.

```bash
make verify     # en qué estado está el servidor
make up         # levantar todo
```

## Documentación

| Documento | Responde |
|---|---|
| [`INSTALL.md`](INSTALL.md) | ¿Cómo lo pongo en marcha por primera vez? |
| [`PRINCIPLES.md`](PRINCIPLES.md) | ¿Qué reglas sigue este stack, y por qué? |
| [`docs/architecture.md`](docs/architecture.md) | ¿Por qué esta herramienta y no otra? |
| [`docs/operations.md`](docs/operations.md) | ¿Qué comando corro en el día a día? |
| [`docs/addons.md`](docs/addons.md) | ¿Cómo llega un módulo a cada entorno? |
| [`docs/restore.md`](docs/restore.md) | ¿Cómo recupero la base y los adjuntos? |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Se rompió algo, ¿qué hago? |

## Cómo está pensado

Tres ideas gobiernan el resto y explican casi todas las decisiones:

**El bind define el acceso, no el firewall.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall, así que un `deny` no alcanza a un puerto publicado por un contenedor. Cada servicio elige uno de cuatro niveles de exposición y ninguno usa `0.0.0.0`.

**Los secretos son archivos, no variables de entorno.** Una env var queda visible en `docker inspect` y en `docker exec … env`. El mecanismo nativo de `secrets:` de Compose evita ambos sin sumar ninguna dependencia.

**Nada se actualiza solo.** Sin auto-update de imágenes, sin instalación de módulos atada al arranque. Cada cambio de versión es un acto deliberado, y las verificaciones viven en `scripts/verify.sh` para poder comprobarlo en cualquier momento.
