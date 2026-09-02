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

Este repo es solo la infraestructura. El código de los módulos de Odoo vive en otros
repositorios, uno por módulo, declarados en `addons/addons.txt` — el panorama completo
de esa relación está en [`docs/vision.md`](docs/vision.md).

## Empezar

```bash
cp .env.production.example .env   # o .env.staging.example / .env.development.example
make secrets-init                 # los secrets que declare esta composición
make config-init                  # los config reales, desde su .example
```

El recorrido completo —qué cuentas hacen falta, en qué orden se levanta cada capa y cómo se verifica— está en [`docs/entorno/levantar-produccion.md`](docs/entorno/levantar-produccion.md). Cada bloque trae su verificación ejecutable, y son los mismos en los tres entornos.

```bash
make verify     # en qué estado está el servidor
make up         # levantar todo
```

## Documentación

| Documento | Responde |
|---|---|
| [`docs/vision.md`](docs/vision.md) | ¿Qué es esto, cómo se relaciona con los repos de módulos, y cómo se levanta un Odoo funcional? |
| [`PRINCIPLES.md`](PRINCIPLES.md) | ¿Qué reglas sigue este stack, y por qué? |
| [`docs/architecture.md`](docs/architecture.md) | ¿Por qué esta herramienta y no otra? |
| [`docs/modular-architecture.md`](docs/modular-architecture.md) | ¿Qué es un stack, y qué declara cada quién? |
| [`docs/stacks.md`](docs/stacks.md) | ¿Qué comparte cada entorno, y qué colisiona si conviven dos? |
| [`docs/entorno/`](docs/entorno/) | ¿Cómo levanto producción, staging o desarrollo? |
| [`docs/modulos/`](docs/modulos/) | ¿Cómo creo o modifico un módulo? |
| [`docs/validacion/`](docs/validacion/) | ¿Cómo confirmo que un cambio anduvo? |
| [`docs/backup-restore/`](docs/backup-restore/) | ¿Cómo hago o recupero un backup? |
| [`docs/operacion/`](docs/operacion/) | ¿Cómo opero una capa del stack en el día a día? |
| [`docs/credenciales/`](docs/credenciales/) | ¿Cómo roto una credencial? |

## Cómo está pensado

Estas ideas gobiernan el resto y explican casi todas las decisiones — el racional
completo, con las alternativas descartadas, vive en
[`docs/architecture.md`](docs/architecture.md) y
[`docs/modular-architecture.md`](docs/modular-architecture.md).

**Con un solo servidor, "robusto" no es alta disponibilidad.** Prioriza evitar pérdida de datos primero, y visibilidad operativa —detectar y diagnosticar caídas rápido— después. Alta disponibilidad real no es alcanzable con un único servidor, así que ninguna decisión se toma para acercarse a ella.

**El repo versiona la forma; el operador solo aporta configs.** Es un catálogo de stacks —cada uno un contenedor con todo lo suyo adentro: imagen, config, scripts, units— más una manera de componerlos. Lo único que varía entre un deployment y otro son archivos de config gitignoreados; `git pull` no toca ninguno.

**El bind define el acceso, no el firewall.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall, así que un `deny` no alcanza a un puerto publicado por un contenedor. Cada servicio elige uno de cuatro niveles de exposición y ninguno usa `0.0.0.0`.

**Los secretos son archivos, no variables de entorno.** Una env var queda visible en `docker inspect` y en `docker exec … env`. El mecanismo nativo de `secrets:` de Compose evita ambos sin sumar ninguna dependencia.

**Los backups van por snapshot, no por WAL continuo.** En Odoo la base no es todo el estado —el filestore es la otra mitad, y no tiene equivalente al WAL—, así que la palanca real del RPO es la frecuencia del snapshot, no la granularidad del archivado.

**Un entorno es un checkout, no una carpeta.** Producción, prueba y desarrollo componen los mismos stacks de la misma forma; lo que cambia es qué `.env` trae cada checkout y qué stacks activa. Nada se actualiza solo —sin auto-update de imágenes, sin instalación de módulos atada al arranque— y cada stack trae su propio `verify.sh` para comprobar su estado en cualquier momento.
