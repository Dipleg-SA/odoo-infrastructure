# Levantar staging

## Cuándo se usa

Puesta en marcha del segundo stack, en el mismo servidor que producción — necesario antes de validar cualquier cambio de módulo (ver [gestionar-modulo § Actualizar](../modulos/gestionar-modulo.md#actualizar)) o de correr el simulacro semestral de restore. Asume producción ya operativa: si este es el primer stack del servidor, el procedimiento es [levantar-produccion](levantar-produccion.md) entero.

Son los **mismos nueve bloques y los mismos comandos** que producción: eso lo dice su entrypoint, así que `make nginx-up` levanta acá dos contenedores en vez de tres. Dos bloques no corresponden y se saltean.

## Objetivo

Un segundo stack con su propio hostname, su propio certificado y su propio túnel, **sembrado con los datos de producción por un restore**. Sembrarlo y hacer el simulacro de restore son la misma operación — es la ocasión natural para el ejercicio que [`PRINCIPLES.md`](../../../PRINCIPLES.md) exige y que siempre se posterga.

| Bloque | Acá | |
|---|---|---|
| 1 · Prerrequisitos | solo el Tunnel propio | ✓ |
| 2 · Repositorio | 7 secrets, tres de ellos copiados de producción | ✓ |
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

**Objetivo** — el repo clonado en su propio directorio, con `.env` y los 7 secrets de este entrypoint cargados y validados. Nada levantado todavía.

**A mano** — `.env.staging.example` deja vacías las claves de este entorno y explica cada una donde se edita. Más abajo en este mismo bloque, `config-init` bootstrapea `r2.env` (gitignoreado) y lo editás junto con el resto.

Lleva el **bucket y endpoint de R2 de producción**, letra por letra, porque es su
repositorio el que se restaura. `PUBLIC_HOSTNAME` sí es de `.env`, y es el de prueba,
distinto del de producción. `SMTP_HOST`/`SMTP_USER`/`ALERT_EMAIL_FROM`/`ALERT_EMAIL_TO`
son los mismos de producción: los usa `failure-notify.sh` si falla `cert-renew`, no
Odoo. Si copiás una clave de más desde el `.env` de producción, dejala con valor o
borrala: `make host-verify` marca las vacías y las ausentes.

> **No declares `COMPOSE_PROFILES`.** Prueba no lleva dnsmasq: corre sobre el 53 con el
> stack de red del host y no admite una segunda instancia. Copiar el `.env` de
> producción con `COMPOSE_PROFILES=lan` es la forma de romperlo.

> **Que prueba no respalde es estructural.** Su entrypoint le pone `profiles: [restore]`
> al stack `backup`, así que queda fuera de la composición por defecto y
> `up-timers` no instala los timers de backup. La segunda capa es la credencial:
> la de R2 de este checkout tiene que ser **de solo lectura**.

| Origen | Secrets | |
|---|---|---|
| Generados | `postgres_password` · `odoo_admin_password` | `secrets-init` los saca de `openssl`; no se tocan |
| Copiados de producción | `restic_password` · `restic_r2_credentials` · `zeptomail_smtp_password` | Los dos primeros abren **su** repositorio: sin los mismos valores no hay nada que restaurar, y el de R2 en versión **solo lectura**. El de ZeptoMail es la misma cuenta — no hace falta un Mail Agent propio para prueba |
| De Cloudflare | `cloudflare_api_token` · `cloudflare_tunnel_token` | El API token puede ser el mismo de producción — es la misma zona. El del Tunnel es el del Tunnel del bloque 1 |

```bash
git clone git@github.com:tu-organizacion/odoo-infrastructure.git odoo-staging && cd odoo-staging
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

Checkout propio, como producción: `.env`, `secrets/`, `state/` y el árbol de addons son de este directorio y de ningún otro.

```bash
cp .env.staging.example .env
nano .env
```

**El `.env` se completa antes de `secrets-init`, no después.** El script le pregunta a la composición cuáles secrets lleva este stack, y eso lo dice `COMPOSE_FILE`.

```bash
make secrets-init
nano -L secrets/cloudflare_api_token   # -L: sin salto de línea final
nano secrets/cloudflare_tunnel_token
nano secrets/restic_r2_credentials
nano secrets/restic_password
nano secrets/zeptomail_smtp_password   # mismo valor que producción
```

```bash
sudo make secrets-perms
set -a; . ./.env; set +a
```

```bash
make config-init
```

Bootstrapea de una sola vez `r2.env` y el de nginx y postgres. `postgresql.conf` sirve tal cual; `odoo.conf` ya no bootstrapea nada —es un archivo versionado, sin SMTP para editar—; los otros dos quedan con un placeholder:

```bash
nano stacks/nginx/config/server-tls.conf   # TU_DOMINIO → el hostname de staging (4 apariciones)
nano stacks/backup/config/r2.env           # TU_ENDPOINT y TU_BUCKET — los de PRODUCCIÓN, letra por letra
```

```bash
make host-verify
```

Repite los chequeos de host —ya deberían pasar, es el mismo servidor— y agrega los propios de este checkout: `.env` sin claves vacías, la identidad declarada del stack, y permisos y GID de los 7 secrets.

---

## 3 · Edge

**Objetivo** — el certificado propio de staging emitido, nginx sirviendo con él y el túnel propio conectado.

**A mano** — el Tunnel se creó en el bloque 1; `server-tls.conf` ya lo bootstrapeaste y editaste en el bloque 2 —con el hostname de staging, distinto del de producción—. Sin `dnsmasq` en este stack, no hace falta tocar `stacks/dnsmasq/`.

```bash
make cert-issue && make nginx-up
make cloudflared-up
sudo make up-timers
```

**Primero el certificado, después el proxy:** nginx no arranca si el archivo no existe, y con DNS-01 certbot no necesita que nginx esté vivo para emitirlo. `cloudflared` va en línea propia y no encadenado con `&&`: no depende del certificado ni de que nginx haya arrancado. El hostname de staging va a dar 502 hasta el bloque 6.

`up-timers` va acá y no más adelante porque **la renovación del certificado es la única unit que le corresponde a este stack** — no respalda, así que no lleva timers de backup. Se instala con el nombre del proyecto adelante (`staging-cert-renew.timer`), así que no pisa las de producción. Sin esto, el certificado de staging vence a los 90 días.

```bash
make nginx-verify
make certbot-verify
make cloudflared-verify
```

`nginx-verify` cubre el servicio `healthy`, que `server-tls.conf` no tenga el placeholder de `.example` sin reemplazar, el `server_name`, las tres rutas de Odoo, que la cadena nginx → Odoo responda de verdad, y el log de nginx sin errores. Los días que le quedan al certificado, el timer de renovación recién instalado y el token de la API de Cloudflare los cubre `certbot-verify`, aparte; las conexiones del Tunnel las cubre `cloudflared-verify` — nginx no sabe nada de ninguno de los dos. `dnsmasq` sale como omitido: este stack no lo trae.

---

## 4 · Database

**Objetivo** — la base y el filestore sembrados desde el repositorio de backups de producción — el mismo restore que exige el simulacro semestral.

**A mano** — nada: `postgresql.conf` ya lo bootstrapeó `config-init` en el bloque 2, y no necesita edición.

```bash
make postgres-up
make restore
```

`restore` trae el filestore y la base del último snapshot de producción, en ese orden: primero el filestore, después la base. Al revés dejaría filas apuntando a adjuntos que no existen, que es destructivo y silencioso.

No hace falta reaplicar ninguna contraseña después: el dump es **lógico**, así que trae los datos y no los roles del cluster de origen. El rol `odoo` de este checkout conserva la clave que `secrets-init` le generó.

```bash
make postgres-verify
```

Igual que en producción: el servicio `healthy`, que acepte conexiones, los logs sin errores de permisos, ningún puerto publicado, y las conexiones de Odoo dentro de `max_connections`.

---

## 5 · Addons

**Objetivo** — el árbol de módulos de la rama `-stag` en disco y la imagen de Odoo construida.

**A mano** — completar `addons/addons.txt`, que `config-init` ya bootstrapeó en el bloque 2, con los mismos repos que producción; la rama la elige `ADDONS_BRANCH` en `.env`, no el manifiesto.

```bash
nano addons/addons.txt
```

```bash
make repo-sync && make build
```

```bash
make repo-status
```

Encabeza con la rama declarada (`<versión>-stag`) y sigue con una fila por repo del manifiesto, todas en `limpio`. Un `huérfano: categoría/nombre` al final es un directorio que quedó en disco después de sacarlo del manifiesto.

---

## 6 · Odoo

**Objetivo** — Odoo sirviendo por el hostname de staging, con los datos de producción adentro.

**A mano** — `odoo.conf` ya lo bootstrapeó `config-init` en el bloque 2. No hace falta editar `smtp_server`/`port`/`user`: `ODOO_DISABLE_SMTP=1` los fuerza vacíos, sin importar lo que traiga el `.example`. La base no arranca vacía, así que no hay `-i base` ni contraseña de `admin` por defecto: **las credenciales son las de producción**, y eso incluye a los usuarios reales. Es la razón por la que este stack fuerza `ODOO_DISABLE_SMTP=1`.

```bash
make odoo-up && make odoo-logs
```

Sin `-i base` de por medio, el entrypoint oficial arranca directo. Esperá igual `HTTP service (werkzeug) running` y cortá los logs con Ctrl-C.

```bash
make odoo-verify
```

Igual que en producción, salvo `smtp_server`: `ODOO_DISABLE_SMTP=1` lo fuerza vacío, así que ese chequeo sale omitido, no en verde.

---

## 7 · Backup — no corresponde

Staging **lee** del repositorio de backups de producción, no escribe en él: no trae la capa, no tiene timers de backup y `make backup-run` falla a propósito con "este stack no incluye la capa de backups". Lo único que respalda a staging es que se puede volver a sembrar corriendo el bloque 4 de nuevo.

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

Los stacks ausentes salen omitidos, no en rojo. Lo que sí tiene que pasar: el certificado vigente con su timer activo, y las tres rutas de Odoo en nginx.

- [ ] `make verify` sale con exit `0`
- [ ] `make backup-run` **rechazado** por `require-backups` — es lo que protege los backups de producción
- [ ] El certificado es el de staging, no el de producción, y su timer está activo
- [ ] El chequeo del apéndice está hecho
- [ ] El RTO de este restore quedó anotado — ver [restore-simulacro-semestral](../backup-restore/restore-simulacro-semestral.md)

---

## Apéndice — lo que no se corre en el servidor

El ingreso público entra solo por el túnel: prueba no tiene `dnsmasq` y su publicación es en loopback, para llegar por túnel SSH desde el propio servidor. Desde cualquier máquina fuera de la LAN:

```bash
HOST_STAG='el-hostname-de-staging'
curl -sI "https://$HOST_STAG/web/login" | grep -iE "^HTTP|^server:|^cf-ray:"
```

Tienen que salir los tres headers: solo Cloudflare agrega `server:` y `cf-ray:`. Si da 502, confirmá el Origin Server Name del Tunnel de staging — es el campo que más se copia mal del de producción.
