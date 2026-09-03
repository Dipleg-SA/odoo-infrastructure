# CLAUDE.md

Guía para Claude Code (claude.ai/code) al trabajar en este repositorio.

Acá va **solo lo que no se deduce leyendo el repositorio**. Las reglas están en [`PRINCIPLES.md`](PRINCIPLES.md), la forma del árbol y por qué es así en [`ARCHITECTURE.md`](ARCHITECTURE.md), y cómo se corre cada cosa en `make help`. Nada de eso se repite acá: un hecho escrito dos veces es un hecho que hay que mantener dos veces.

## Idioma

**Todo el repositorio está en español**: comentarios de código, documentación, mensajes de commit y salida de los scripts. Escribí en español, en la misma voz directa que ya usan los archivos. Los identificadores (servicios, variables, targets) quedan en inglés donde ya lo están.

El estilo de comentarios en archivos versionados de código y config es obligatorio y vive en [`.claude/rules/comment-style.md`](.claude/rules/comment-style.md).

## Comandos

`make help` lista todo, agrupado, y se genera solo desde el `Makefile` — no lo dupliques en documentación.

Lo que sí hay que saber: **son dos verificaciones distintas y no se reemplazan.** `make test` corre sin Docker levantado ni red, sobre lo que se puede afirmar leyendo el repositorio. `make verify` dice en qué estado está un deploy real, y **eso** necesita el sistema corriendo.

`tests/` cubre el contrato de los entrypoints (`docker compose config`), `addons.sh` de punta a punta contra repos git de verdad, y —con los stubs de `tests/stubs/`, que registran cada invocación— los derivadores de los scripts. Al tocar un script, la pregunta es si el test **falla** cuando se rompe lo que dice cubrir: mutá y comprobalo, que ya aparecieron aserciones que pasaban por el motivo equivocado.

Al tocar un compose, la verificación más fuerte es que **la config resuelta no cambie**:

```bash
docker compose config > /tmp/antes.yaml
# … cambio …
docker compose config | diff /tmp/antes.yaml -
```

Para scripts, `bash -n` y después correrlos de verdad. **Correr `make verify` encontró que la mitad de sus propios `ok` mentían** cuando los servicios estaban abajo; asumí que cualquier verificación no ejecutada puede estar mintiendo.

## Cosas que no se deducen leyendo un archivo solo

- **`entrypoint.sh` de Odoo genera config en runtime.** El `addons_path` sale de un glob sobre cuatro categorías en orden de precedencia (`enterprise > custom-addons > oca > third-party`); `admin_passwd` y `smtp_password` se appendean al conf desde su secret, y `smtp_server`/`port`/`user` desde `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER` del `.env`. Por eso `odoo.conf` se versiona tal cual, sin `.example`: no le queda ningún valor por deployment. `ODOO_DISABLE_SMTP=1` gana sobre el `.env` y fuerza `smtp_server` vacío.
- **La imagen de Odoo lee sus pines de un contexto de build aparte.** `requirements.txt` queda fuera del contexto de build, así que llega por `additional_contexts` y `COPY --from`. El corchete de `requirements.tx[t]` no es un typo: hace el `COPY` opcional —con cero matches, un glob normal aborta el build— para que un checkout sin pines buildee igual. El `RUN` que lo instala va condicionado con `if`, no con `&&`: un `;` ahí dejaría que un `pip install` fallado devuelva 0 y produzca una imagen sin dependencias.
- **Las units de systemd llevan el nombre del proyecto adelante**, y `scripts/timers.sh` es dueño único de ese nombre y de qué units corresponden — lo deriva de la composición, no de una lista. Las verificaciones le preguntan en vez de repetir nombres, y con eso dos checkouts en el mismo host no se pisan las units.
- **Cada stack es dueño de qué se chequea y qué se espera de él.** El `verify` de arriba orquesta: corre el de cada stack presente y junta resultados, sin saber qué espera ninguno. Los runbooks nombran el comando; los valores esperados no se duplican en la documentación.

## Invariantes que viven en dos archivos

Están duplicados por necesidad —hay formatos que no interpolan variables— y las verificaciones los cruzan. Si tocás un lado, corré la verificación correspondiente:

| Un lado | El otro | Qué pasa si divergen |
|---|---|---|
| categorías en `addons.sh` | bucle `for category` en el entrypoint de Odoo | los módulos se clonan y nunca se cargan |
| rama de addons en `.env` | tag `FROM odoo:` del Dockerfile | ramas de una versión montadas en un Odoo de otra |
| umbral de la alerta de backup viejo | `RESTIC_MAX_AGE` del healthcheck | el contenedor se pone rojo antes de que nadie reciba el aviso |
| GID de cada secret | usuario real del contenedor que lo lee | el consumidor no puede leerlo |

Uno más, real pero **sin verificación que lo cruce**: `RESTIC_MAX_AGE` es cadencia del
`OnCalendar` más margen, así que mover el timer sin tocarlo deja el contenedor unhealthy
para siempre. Vive en los comentarios de los dos archivos y en ningún chequeo.

## Rarezas de herramienta que cuestan horas

- **Un `--profile` explícito REEMPLAZA a `COMPOSE_PROFILES`, no se suma.** Enumerar la composición con `--profile cert` descarta el `lan` que trajo el `.env` del operador. Para preguntar por todo hay que fusionar en la variable: `COMPOSE_PROFILES="cert,restore${COMPOSE_PROFILES:+,$COMPOSE_PROFILES}"`.
- **Un servicio con `profiles:` inactivo no se valida.** `docker compose config` sale exit 0 sin haberlo mirado: un falso verde, no una prueba de que ese archivo esté bien.
- **Nombrar un servicio con `profiles:` explícito en `up`/`run` salta el filtro del perfil**, aunque esté inactivo — es lo que hace posible el restore de staging sin activar nada, y también significa que `docker compose up dnsmasq` en un VPS sin LAN no falla con "no such service" como parecería razonable esperar. Lo que pasa en cambio depende de si su config ya existe: si nunca se bootstrapeó, Docker monta un directorio vacío y el contenedor no arranca; si quedó de una activación anterior, arranca de verdad y queda escuchando en el `53` del host.
- **`include:` resuelve las rutas relativas de cada archivo incluido contra *su propia* carpeta**, no contra la del que lo incluye. También acepta que cada archivo nombre su propio `env_file`, y el mismo archivo corriendo solo lee ese mismo entorno desde su carpeta.
- **`docker compose run` acepta `--user`**, así que una operación puntual puede elevarse en la invocación sin que el servicio se declare root.
- `docker compose port` devuelve `invalid IP:0` con exit 0 para un puerto **no** publicado — no cadena vacía.
- `alloy validate` solo valida sintaxis: acepta constantes inexistentes con exit 0. Para probar que una referencia resuelve hay que ejecutar Alloy y leer su API.
- `dockerd` no arranca si `daemon.json` tiene claves desconocidas, incluidos comentarios simulados.

## Documentación: qué va dónde

| Archivo | Contenido |
|---|---|
| `PRINCIPLES.md` | las reglas, en imperativo, como restricciones y no como formas del árbol |
| `ARCHITECTURE.md` | panorama de conjunto, relación con los repos de módulos, por qué esta herramienta y no otra, qué es un stack y qué declara cada quién, qué comparte cada entorno, y la estructura |
| `docs/entorno/` · `docs/modulos/` · `docs/validacion/` · `docs/backup-restore/` · `docs/operacion/` · `docs/credenciales/` | manual de procedimientos: un archivo por procedimiento, genérico. Plantilla — Cuándo se usa · Objetivo · A mano · Comandos · Verificación |
| `CONTRIBUTING.md` | cómo proponer un cambio: qué leer antes, idioma, verificación, convención de PR |
| `SECURITY.md` | cómo reportar una vulnerabilidad, y qué está fuera de alcance |

El contexto histórico, los incidentes y las justificaciones largas van a `ARCHITECTURE.md`, **nunca inline** en el código.

## De dónde viene este repositorio

Este es el **producto**: la versión genérica y agnóstica del stack, con historia propia —raíz propia, sin ancestro común— y sin rastros de ningún deployment concreto.

El deployment original del que salió vive en otro repositorio, con su propia historia. **Nada de ese repositorio se trae acá**: es el que tiene la IP pública, el dominio y el hardware que esta versión elimina.

Al escribir acá, cualquier valor que solo sirva a un deployment concreto —hostnames, IPs, cantidades de RAM, fechas, nombres de proveedores como ejemplo obligatorio— es un defecto, no un detalle.
