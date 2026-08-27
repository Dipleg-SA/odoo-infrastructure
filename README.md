# odoo-infrastructure

Infraestructura Docker autoalojada para una instancia de Odoo, operada por una sola persona sobre un único servidor.

Once stacks bajo `stacks/`, uno por contenedor, con su imagen y su config adentro: reverse proxy con TLS propio, túnel de ingreso sin puertos abiertos, acceso por red local, la base, la aplicación, backups por snapshot y observabilidad con alerting.

## Qué levanta

Un stack es un contenedor con todo lo suyo en su carpeta: `compose.yaml`, `image/`, `config/`, sus scripts y sus units.

| Stack | Qué hace | Entornos |
|---|---|---|
| `nginx` | Reverse proxy: TLS, rate-limit del login, ruteo del bus | los tres |
| `certbot` | Emite y renueva el certificado por DNS-01 | producción · prueba |
| `cloudflared` | Túnel de ingreso, sin puertos abiertos en el router | producción · prueba |
| `dnsmasq` | Resuelve el hostname a la IP local, para clientes en la LAN | producción, si hay servidor local |
| `postgres` | La base | los tres |
| `odoo` | La aplicación | los tres |
| `backup` | Respalda y restaura: dump y filestore en un snapshot de restic | producción · prueba (solo restaura) |
| `prometheus` · `loki` · `grafana` · `alloy` | Métricas, logs, consulta y alerting | producción |

`envs/production.yaml` no es monolítico: declara las redes, los secretos y los volúmenes compartidos, y suma el `compose.yaml` de cada stack con `include:`. El nombre del stack no está ahí — vive en `.env`, junto a `COMPOSE_FILE`, que es lo que elige qué entorno se levanta.

## Empezar

```bash
cp .env.production.example .env   # o .env.staging.example / .env.development.example
make secrets-init                 # los secrets que declare esta composición
make config-init                  # los config reales, desde su .example
```

El recorrido completo —qué cuentas hacen falta, en qué orden se levanta cada capa y cómo se verifica— está en [`docs/runbooks/entorno/levantar-produccion.md`](docs/runbooks/entorno/levantar-produccion.md). Cada bloque trae su verificación ejecutable, y son los mismos en los tres entornos.

```bash
make verify     # en qué estado está el servidor
make up         # levantar todo
```

## Documentación

| Documento | Responde |
|---|---|
| [`PRINCIPLES.md`](PRINCIPLES.md) | ¿Qué reglas sigue este stack, y por qué? |
| [`docs/architecture.md`](docs/architecture.md) | ¿Por qué esta herramienta y no otra? |
| [`docs/modular-architecture.md`](docs/modular-architecture.md) | ¿Qué es un stack, y qué declara cada quién? |
| [`docs/stacks.md`](docs/stacks.md) | ¿Qué comparte cada entorno, y qué colisiona si conviven dos? |
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

**Nada se actualiza solo.** Sin auto-update de imágenes, sin instalación de módulos atada al arranque. Cada cambio de versión es un acto deliberado, y cada stack trae su propio `verify.sh` para poder comprobar su estado en cualquier momento.
