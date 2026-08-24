# Levantar staging

## Cuándo se usa

Puesta en marcha del segundo stack, en el mismo servidor que producción — necesario antes de validar cualquier cambio de módulo (ver [actualizar-modulo](../modulos/actualizar-modulo.md)) o de correr el simulacro semestral de restore. Asume producción ya operativa: si este es el primer stack del servidor, el procedimiento es [levantar-produccion](levantar-produccion.md) entero.

Son los **mismos nueve bloques y los mismos comandos** que producción: `capa.sh` resuelve qué servicios trae este stack, así que `make edge-up` levanta acá dos contenedores en vez de tres. Dos bloques no corresponden y se saltean.

## Objetivo

Un segundo stack con su propio hostname, su propio certificado y su propio túnel, **sembrado con los datos de producción por un restore**. Sembrarlo y hacer el simulacro de restore son la misma operación — es la ocasión natural para el ejercicio que [`PRINCIPLES.md`](../../../PRINCIPLES.md) exige y que siempre se posterga.

| Bloque | Acá | |
|---|---|---|
| 1 · Prerrequisitos | solo el Tunnel propio | ✓ |
| 2 · Repositorio | 8 secrets, tres de ellos copiados de producción | ✓ |
| 3 · Edge | certificado y túnel propios, **sin `dnsmasq`** | ✓ |
| 4 · Database | sembrada por restore desde el repositorio de producción | ✓ |
| 5 · Addons | la rama `-stag` de cada repo del manifiesto | ✓ |
| 6 · Odoo | con los datos de producción adentro | ✓ |
| 7 · Backup | **no corresponde** — staging lee del repositorio de producción, no escribe | — |
| 8 · Monitoring | **no corresponde** — la observabilidad es exclusiva de producción | — |
| 9 · Cierre | ✓ | ✓ |

Los tres ausentes son exclusivos de producción, y el `53` en `network_mode: host` no admite un segundo `dnsmasq` de ninguna forma. Ver [stacks.md](../../stacks.md) para qué comparte cada entorno.

---

## 1 · Prerrequisitos

**Objetivo** — lo único que no resolvió ya producción en este host.

| Prerrequisito | Runbook | Te deja |
|---|---|---|
| Tunnel de Cloudflare **propio** | [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md) | `secrets/cloudflare_tunnel_token` |

No es el de producción: **el token es lo que distingue a los dos stacks**. Mismos campos, con el hostname de staging en Subdomain y en **Origin Server Name**, y `https://nginx:443` como Service.

Todo lo demás ya está: la versión de Docker Engine/Compose y su arranque automático ([configurar-docker-host](configurar-docker-host.md)), y la rotación de logs del daemon —aplicada antes del primer contenedor de producción, así que cualquier contenedor nuevo, incluidos los de este stack, ya nace con ella—. No hay nada que instalar o reconfigurar a nivel de sistema operativo.

---

## 2 · Repositorio

**Objetivo** — el repo clonado en su propio directorio, con `.env` y los 8 secrets de este entrypoint cargados y validados. Nada levantado todavía.

**A mano** — `.env.stag.example` deja vacías las claves de este entorno y explica cada una donde se edita. Dos cosas que no se deducen ahí: `PGBACKREST_STANZA`, `R2_ENDPOINT` y `R2_BUCKET` llevan **los valores de producción**, letra por letra, porque es su repositorio el que se restaura; y `PUBLIC_HOSTNAME` es el de staging, distinto del de producción. Si copiás una clave de más desde el `.env` de producción, dejala con valor o borrala: `make host-verify` marca las vacías.

> **`PG_ARCHIVE_MODE=off` es la línea que protege los backups de producción.** Staging apunta a la stanza de producción para poder restaurar; con el archivado prendido su propio Postgres le empuja WAL a ese repositorio y lo contamina desde el entorno que existe para romper cosas. Lo verifica `make db-verify`, que en un stack sin capa de backups **exige** que esté apagado.

Los 8 secrets se reparten en tres grupos, y solo el del Tunnel es trabajo nuevo:

| Grupo | Cuáles | De dónde salen |
|---|---|---|
| Generados | `postgres_password` · `pgbouncer_credentials` · `odoo_admin_password` | `secrets-init` los saca de `openssl`; no se tocan |
| Copiados de producción | `restic_password` · `pgbackrest_r2_credentials` · `restic_r2_credentials` | Abren **su** repositorio: sin los mismos valores no hay nada que restaurar |
| De Cloudflare | `cloudflare_api_token` · `cloudflare_tunnel_token` | El API token puede ser el mismo de producción — es la misma zona. El del Tunnel es el del Tunnel del bloque 1 |

```bash
git clone git@github.com:tu-organizacion/odoo-infrastructure.git odoo-staging && cd odoo-staging
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

Checkout propio, como producción: `.env`, `secrets/`, `state/` y el árbol de addons son de este directorio y de ningún otro.

```bash
cp .env.stag.example .env
nano .env
```

**El `.env` se completa antes de `secrets-init`, no después.** El script le pregunta a la composición cuáles secrets lleva este stack, y eso lo dice `COMPOSE_FILE`.

```bash
make secrets-init
nano -L secrets/cloudflare_api_token   # -L: sin salto de línea final
nano secrets/cloudflare_tunnel_token
nano secrets/pgbackrest_r2_credentials
nano secrets/restic_r2_credentials
nano secrets/restic_password
```

```bash
sudo make secrets-perms
set -a; . ./.env; set +a
```

```bash
make host-verify
```

Repite los chequeos de host —ya deberían pasar, es el mismo servidor— y agrega los propios de este checkout: `.env` sin claves vacías, la identidad declarada del stack, y permisos y GID de los 8 secrets.

---

## 3 · Edge

**Objetivo** — el certificado propio de staging emitido, nginx sirviendo con él y el túnel propio conectado.

**A mano** — ninguno: el Tunnel se creó en el bloque 1.

```bash
make cert-issue && make edge-up
sudo make timers-install
```

**Primero el certificado, después el proxy:** nginx no arranca si el archivo no existe, y con DNS-01 certbot no necesita que nginx esté vivo para emitirlo. El hostname de staging va a dar 502 hasta el bloque 6.

`timers-install` va acá y no más adelante porque **la renovación del certificado es la única unit que le corresponde a este stack** — no respalda, así que no lleva timers de backup. Se instala con el nombre del proyecto adelante (`staging-cert-renew.timer`), así que no pisa las de producción. Sin esto, el certificado de staging vence a los 90 días.

```bash
make edge-verify
```

Cubre los dos servicios `healthy`, la config renderizada sin variables sin sustituir, el `server_name`, los días que le quedan al certificado, el timer de renovación recién instalado, las conexiones del Tunnel y el log de nginx sin errores. `dnsmasq` sale como omitido: este stack no lo trae.

---

## 4 · Database

**Objetivo** — la base y el filestore sembrados desde el repositorio de backups de producción — el mismo restore que exige el simulacro semestral.

**A mano** — ninguno.

```bash
make restore-seed
```

Levanta los dos contenedores del perfil `restore`, restaura la base y después el filestore, y los baja. **El orden importa y es el inverso al del backup**: un filestore más nuevo que la base deja archivos huérfanos, inofensivos; uno más viejo deja filas apuntando a archivos que no existen.

El target encierra dos cosas que no pueden quedar a criterio de quien lo corre: el `--archive-mode=off` del restore —sin él, el cluster restaurado hereda el `archive_command` del backup y empieza a empujar WAL a la stanza de producción— y la guarda que lo hace fallar en un stack que sí respalda. **Va antes de `db-up`**: pgBackRest no restaura sobre un cluster vivo.

```bash
make db-up
```

```bash
make db-verify
```

Lo que tiene que pasar acá y no en producción: `archive_mode` **APAGADO**. El resto es igual — los dos servicios `healthy`, ningún puerto publicado y la autenticación real a través de PgBouncer.

---

## 5 · Addons

**Objetivo** — el árbol de módulos de la rama `-stag` en disco y la imagen de Odoo construida.

**A mano** — completar `addons/addons.txt` con los mismos repos que producción; la rama la elige `ADDONS_BRANCH` en `.env`, no el manifiesto.

```bash
cp addons/addons.txt.example addons/addons.txt
cp addons/requirements.txt.example addons/requirements.txt
nano addons/addons.txt
```

```bash
make addons-sync && make build
```

```bash
make addons
```

Encabeza con la rama declarada (`<versión>-stag`) y sigue con una fila por repo del manifiesto, todas en `limpio`.

---

## 6 · Odoo

**Objetivo** — Odoo sirviendo por el hostname de staging, con los datos de producción adentro.

**A mano** — ninguno. La base no arranca vacía, así que no hay `-i base` ni contraseña de `admin` por defecto: **las credenciales son las de producción**, y eso incluye a los usuarios reales. Es la razón por la que este stack saca el correo saliente con `SMTP_HOST: ""`.

```bash
make odoo-up && make odoo-logs
```

```bash
make odoo-verify
```

---

## 7 · Backup — no corresponde

Staging **lee** del repositorio de backups de producción, no escribe en él: no trae la capa, no tiene timers de backup y `make backup` falla a propósito con "este stack no incluye la capa de backups". Lo único que respalda a staging es que se puede volver a sembrar corriendo el bloque 4 de nuevo.

---

## 8 · Monitoring — no corresponde

La observabilidad es exclusiva de producción: un segundo Prometheus y un segundo Grafana en el mismo servidor duplicarían el consumo para observar el entorno que existe para romper cosas. `make verify` marca la capa como omitida, no como fallada.

---

## 9 · Cierre

**Objetivo** — el stack completo convergido con un solo `make up`, y verificado capa por capa.

```bash
make up
```

```bash
make verify
```

Las capas ausentes salen como `--`, no en rojo. Lo que sí tiene que pasar: `archive_mode APAGADO`, el certificado vigente con su timer activo, y las tres rutas de Odoo en nginx.

- [ ] `make verify` sale con exit `0`
- [ ] `archive_mode` apagado — es lo que protege los backups de producción
- [ ] El certificado es el de staging, no el de producción, y su timer está activo
- [ ] El chequeo del apéndice está hecho
- [ ] El RTO de este restore quedó anotado — ver [restore-simulacro-semestral](../backup-restore/restore-simulacro-semestral.md)

---

## Apéndice — lo que no se corre en el servidor

Uno solo: staging no publica ningún puerto y no tiene `dnsmasq`, así que el único camino de ingreso es el túnel. Desde cualquier máquina fuera de la LAN:

```bash
HOST_STAG='el-hostname-de-staging'
curl -sI "https://$HOST_STAG/web/login" | grep -iE "^HTTP|^server:|^cf-ray:"
```

Tienen que salir los tres headers: solo Cloudflare agrega `server:` y `cf-ray:`. Si da 502, confirmá el Origin Server Name del Tunnel de staging — es el campo que más se copia mal del de producción.
