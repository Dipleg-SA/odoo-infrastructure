# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Idioma

**Todo el repositorio está en español**: comentarios de código, documentación, mensajes de commit y salida de los scripts. Escribí en español, en la misma voz directa que ya usan los archivos. Los identificadores (servicios, variables, targets) quedan en inglés donde ya lo están.

El estilo de comentarios en archivos versionados de código y config es obligatorio y vive en `.claude/rules/comment-style.md`.

## Comandos

No hay suite de tests: la verificación del sistema **es** `scripts/verify.sh`.

```bash
make verify                 # estado del servidor entero, capa por capa
make verify-<capa>          # host | edge | db | odoo | backups | observability
make up / down / logs / ps
make addons-sync            # rearma el árbol de addons desde config/odoo/addons.txt
make odoo-install MODULES=x # -i explícito; MODULES es obligatorio
make odoo-update MODULES=x  # -u explícito
make backup / backup-full / backup-check
make secrets-init / secrets-perms / secrets-check
```

Al tocar un `compose.*.yaml`, la verificación más fuerte es que **la config resuelta no cambie**:

```bash
docker compose config > /tmp/antes.yaml
# … cambio …
docker compose config | diff /tmp/antes.yaml -
```

Para scripts, `bash -n scripts/<x>.sh` y después correrlos de verdad. **Correr `make verify` encontró que la mitad de sus propios `ok` mentían** cuando los servicios estaban abajo; asumí que cualquier verificación no ejecutada puede estar mintiendo.

## Arquitectura

`compose.yaml` es solo redes, secrets y un `include:` por capa. Nunca un archivo monolítico, nunca `compose.override.yaml` — ese nombre dispara el autoload implícito de Compose.

| Capa | Servicios | Módulo |
|---|---|---|
| Borde | `traefik` · `cloudflared` · `dnsmasq` | `compose.edge.yaml` |
| Datos | `postgres` · `pgbouncer` | `compose.db.yaml` |
| Aplicación | `odoo` | `compose.odoo.yaml` |
| Protección | `backup` (restic) + pgBackRest dentro de Postgres | `compose.backups.yaml` |
| Observación | `prometheus` · `loki` · `grafana` · `alloy` | `compose.observability.yaml` |

Cosas que no se deducen leyendo un archivo solo:

- **pgBackRest no tiene contenedor propio**: vive dentro de la imagen de Postgres, porque `archive_command` lo ejecuta el proceso de la base.
- **`docker/odoo/entrypoint.sh` genera config en runtime**. El `addons_path` sale de un glob sobre cuatro categorías en orden de precedencia (`enterprise > custom-addons > oca > third-party`), y `admin_passwd`, SMTP y credenciales se appendean al conf. `config/odoo/odoo.conf` es solo la base.
- **PgBouncer corre en modo transacción**, lo que rompe `LISTEN/NOTIFY`. Por eso `server_wide_modules` incluye `bus_alt_connection`, que le da al bus su propia conexión directa. Sin ese módulo Odoo arranca igual y el chat en vivo deja de actualizarse.
- **Instalar o actualizar módulos nunca va atado al arranque.** Es un one-off explícito del operador contra `postgres:5432`, no contra PgBouncer.
- **`addons/` está gitignoreado entero.** El único artefacto versionado es el manifiesto `config/odoo/addons.txt`; `scripts/addons.sh` rearma el árbol desde ahí.

## Invariantes que viven en dos archivos

Estos valores están duplicados por necesidad —hay formatos que no interpolan variables— y `verify.sh` los cruza. Si tocás un lado, corré la capa correspondiente:

| Un lado | El otro | Qué pasa si divergen |
|---|---|---|
| `PGBACKREST_STANZA` en `.env` | sección `[nombre]` de `pgbackrest.conf` | el archivado de WAL muere sin error de config |
| categorías en `addons.sh` | bucle `for category` en `entrypoint.sh` | los módulos se clonan y nunca se cargan |
| rama de addons en `.env` | tag `FROM odoo:` del Dockerfile | ramas de una versión montadas en un Odoo de otra |
| `RESTIC_KEEP_*` | `BACKUP_RETENTION_DAYS` | un restore viejo se queda sin adjuntos |
| `RESTIC_MAX_AGE` | `OnCalendar` de `config/systemd/` | el contenedor queda unhealthy para siempre |
| GID de cada secret | usuario real del contenedor que lo lee | el consumidor no puede leerlo (ver abajo) |

## Reglas que cuestan caro de redescubrir

- **El acceso lo define el `ports:`, no el firewall.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall. Cuatro niveles, nunca `0.0.0.0`. Ese criterio **no habla de los binds internos del contenedor**: un proceso que escucha en `0.0.0.0` sin `ports:` no expone nada al host, y a veces es necesario.
- **Los secretos son archivos, nunca variables de entorno** — una env var queda visible en `docker inspect`. Compose fuera de Swarm **ignora `uid`/`gid`/`mode`** de los secrets de archivo, así que un `600` root-owned deja sin lectura a cualquier contenedor no-root. El mapa de GIDs esperados es dueño único de `scripts/secrets-perms.sh`; verificá el usuario real de la imagen, muchas corren distroless.
- **Parametrizá por `.env` solo lo que se usa dentro de un `compose.*.yaml`.** Cuando el valor vive en el archivo de config propio de una herramienta, tiene que llegar por el mecanismo que *esa herramienta* ofrezca: Compose no interpola dentro de archivos bind-mounted. Loki necesita `-config.expand-env=true` **y** un bloque `environment:`, porque expande desde su propio entorno. Traefik trata archivo, flags y env como excluyentes: con su archivo presente no hay valor que inyectar por afuera.
- **Nunca archivos `.example` paralelos** a un config: son una copia que se desincroniza. Si el valor no se puede parametrizar, se elimina o se versiona literal.
- **`scripts/verify.sh` es dueño único de qué se chequea y qué se espera.** `INSTALL.md` nombra el comando; los valores esperados no se duplican en la documentación.
- `docker compose port` devuelve `invalid IP:0` con exit 0 para un puerto **no** publicado — no cadena vacía.
- `alloy validate` solo valida sintaxis: acepta constantes inexistentes con exit 0. Para probar que una referencia resuelve hay que ejecutar Alloy y leer su API.
- `dockerd` no arranca si `daemon.json` tiene claves desconocidas, incluidos comentarios simulados.

## Documentación: qué va dónde

| Archivo | Contenido |
|---|---|
| `PRINCIPLES.md` | las reglas del stack, en imperativo, con el mecanismo que las implementa |
| `INSTALL.md` | puesta en marcha; cuatro bloques por fase (Objetivo · A mano · Comandos · Verificación) |
| `docs/architecture.md` | por qué esta herramienta y no otra, y qué se descartó |
| `docs/stacks.md` | qué comparte cada entorno y las decisiones tomadas para staging y development |
| `docs/roadmap.md` | plan de implementación por etapas |
| `docs/operations.md` · `restore.md` · `troubleshooting.md` · `addons.md` | operación |

El contexto histórico, los incidentes y las justificaciones largas van a `docs/`, **nunca inline** en el código.

## Estado de las ramas

- **`main`** — el deployment original, con `.specs/` (constitución R11, backlog y 7 specs de spec-flow).
- **`producto`** — versión genérica y agnóstica, sin rastros del deployment original: sin IP pública, sin dominio, sin hardware, sin fechas. `PRINCIPLES.md` reemplaza a la constitución y `docs/roadmap.md` al roadmap de spec-flow.

**`producto` no se pushea al `origin` existente**: ese remoto contiene el historial de `main`, con la identidad del deployment que esta rama elimina.

Al escribir en `producto`, cualquier valor que solo sirva a un deployment concreto —hostnames, IPs, cantidades de RAM, fechas, nombres de proveedores como ejemplo obligatorio— es un defecto, no un detalle.
