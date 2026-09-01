# Levantar desarrollo

## Cuándo se usa

Vas a empezar a trabajar en una feature — un módulo nuevo o un cambio sobre uno existente — y necesitás tu propio entorno, aislado de cualquier otro checkout de desarrollo que tengas corriendo. Un checkout por feature, en tu máquina.

Son los **mismos nueve bloques y los mismos comandos** que producción: eso lo dice su entrypoint, así que `make nginx-up` levanta acá un solo contenedor. Dos bloques no corresponden y se saltean.

## Objetivo

Odoo sirviendo por nginx en loopback, sin túnel, sin certificados, sin backups, y **sin ningún valor que pegar a mano**: los dos secrets se generan.

| Bloque | Acá | |
|---|---|---|
| 1 · Prerrequisitos | Docker, y el token de git solo si tu manifiesto tiene repos privados | ✓ |
| 2 · Repositorio | 2 secrets, los dos generados | ✓ |
| 3 · Edge | **solo nginx**, en texto plano: ni túnel, ni certificados, ni `dnsmasq` | ✓ |
| 4 · Database | vacía — la inicializa Odoo en el bloque 6 | ✓ |
| 5 · Addons | tu rama de trabajo | ✓ |
| 6 · Odoo | el sitio en `127.0.0.1` | ✓ |
| 7 · Backup | **no corresponde** | — |
| 8 · Monitoring | **no corresponde** | — |
| 9 · Cierre | + el aislamiento entre checkouts | ✓ |

nginx está presente aunque no haya TLS — es lo que hace honesto al `proxy_mode = True` de `odoo.conf`: sin nadie escribiendo `X-Forwarded-*`, Odoo confía en cabeceras que no existen, y esa diferencia con producción aparece justo en lo que es difícil de reproducir.

---

## 1 · Prerrequisitos

**Objetivo** — tu máquina lista. Dos, y el segundo no siempre.

| Prerrequisito | Runbook | Te deja |
|---|---|---|
| Docker Engine y Compose ≥ 2.20 | [configurar-docker-host](configurar-docker-host.md) | Siempre — solo la instalación; el arranque automático es cosa de un servidor |
| Token de git de solo lectura | [crear-token-git-lectura](crear-token-git-lectura.md) | Si tu manifiesto de addons trae repos privados. Uno por máquina, no por checkout |

**Nada de Cloudflare, R2 ni ZeptoMail.** Development no tiene túnel, ni certificados, ni backups, ni correo saliente: sus dos secrets se generan solos. Es toda la diferencia con [levantar-produccion § 1](levantar-produccion.md#1--prerrequisitos), donde cuatro de esos valores salen de cuentas de terceros.

---

## 2 · Repositorio

**Objetivo** — checkout propio por feature, con `.env` y los 2 secrets generados y con permisos. Nada levantado todavía.

**A mano** — nada que pegar. `.env.development.example` deja cuatro claves y las explica donde se editan; `COMPOSE_FILE` ya viene puesto. La que no se puede olvidar es `COMPOSE_PROJECT_NAME`.

> **El nombre del proyecto es el único aislamiento entre dos checkouts de desarrollo.** De él salen los volúmenes: dos que lo compartan resuelven al mismo `pgdata`, y como corre uno a la vez no colisionan al arrancar — **se pisan los datos en silencio**. Si falta la clave, Compose cae al directorio del compose elegido —`docker`, el mismo en todos los checkouts—, así que olvidarla es exactamente el caso peligroso; el otro es copiar el `.env` de un checkout a otro.

```bash
FEATURE='sale'
git clone git@github.com:tu-organizacion/odoo-infrastructure.git ~/odoo-development-$FEATURE
cd ~/odoo-development-$FEATURE
```

Acá **no** se fija a un tag: el checkout de desarrollo sigue la rama en la que estás trabajando. El `HEAD` detached es un guard-rail del servidor, donde nadie debería estar corrigiendo código.

```bash
cp .env.development.example .env
nano .env
```

**Antes de `secrets-init`, no después:** el script le pregunta a la composición cuáles secrets lleva este stack. El placeholder de `COMPOSE_PROJECT_NAME` es el mismo para todo checkout que no lo cambie, y de ahí salen los volúmenes.

```bash
make secrets-init
```

```bash
sudo make secrets-perms
set -a; . ./.env; set +a
```

`secrets-init` no imprime ningún pendiente: los dos salen de `openssl`.

```bash
make config-init
```

Bootstrapea de una sola vez los config reales de nginx y postgres desde su `.example` — `odoo.conf` ya no bootstrapea nada, es un archivo versionado. Ninguno queda con placeholder: sirven tal cual, sin nada que editar.

```bash
make host-verify
```

Chequea la versión de Compose, `.env` sin claves vacías, la identidad declarada del stack y los permisos de los 2 secrets. El arranque automático de Docker sale omitido sin systemd, y fallado en un Linux que no lo tenga habilitado: en una máquina de trabajo es esperable y no bloquea nada.

---

## 3 · Edge

**Objetivo** — nginx sirviendo en loopback, en texto plano.

**A mano** — nada: de los tres archivos de nginx que este stack monta, los dos reales —`00-http.conf` y `odoo.locations`— ya los bootstrapeó `config-init` en el bloque 2, y `server-plain.conf` viene versionado. Los valores del `.example` ya sirven tal cual (rate-limit, CIDR de Docker); no hace falta editarlos salvo que tu red los necesite distintos. `NGINX_MODE` no se declara: `envs/development.yaml` fija la plantilla sin TLS en el entrypoint. Si dependiera de la variable, un `.env` sin la clave montaría la plantilla con TLS y nginx no arrancaría — no hay certificado.

```bash
make nginx-up
```

Sin `make cert-issue` adelante, que es lo que sí lleva producción: este stack no tiene certbot. Tampoco `dnsmasq` ni el túnel — de la capa edge, acá solo existe el proxy.

```bash
make nginx-verify
```

Omite el `server_name` y el 443, los dos derivados de que este stack sirve en texto plano y no publica ese puerto. El certificado no aparece acá porque no es cosa de `nginx-verify` en ningún entorno: es `certbot-verify`, y development no lo trae.

---

## 4 · Database

**Objetivo** — la base corriendo y vacía.

**A mano** — nada: `postgresql.conf` ya lo bootstrapeó `config-init` en el bloque 2, y no necesita edición.

```bash
make postgres-up
```

```bash
make postgres-verify
```

Exige el servicio `healthy`, que acepte conexiones, los logs sin errores de permisos, que el puerto no esté publicado, y que las conexiones de Odoo entren en `max_connections`.

---

## 5 · Addons

**Objetivo** — el árbol de addons de tu rama en disco y la imagen de Odoo construida.

**A mano** — completar `addons/addons.txt`, que `config-init` ya bootstrapeó en el bloque 2. Si todavía no declaraste ningún repo propio, ver [gestionar-fork § Crear](../modulos/gestionar-fork.md#crear).

```bash
nano addons/addons.txt
```

`ADDONS_BRANCH` en tu `.env` es una rama de feature nueva: todavía no existe en ningún repo del manifiesto. `repo-sync` arma worktrees, no crea ramas — sin este paso falla al primer intento.

```bash
make repo-branch
```

```bash
make repo-sync && make build
```

```bash
make repo-status
```

Encabeza con la rama declarada y sigue con una fila por repo del manifiesto, todas en `limpio`. Un `huérfano: categoría/nombre` al final es un directorio que quedó en disco después de sacarlo del manifiesto.

---

## 6 · Odoo

**Objetivo** — Odoo sirviendo por nginx en loopback.

**A mano** — nada: `odoo.conf` es un archivo versionado, sin nada que bootstrapear ni editar. `ODOO_DISABLE_SMTP=1`, forzado en `envs/development.yaml`, deja `smtp_server` vacío pase lo que pase en `.env`.

```bash
make odoo-up && make odoo-logs
```

La base arranca vacía: el entrypoint detecta que no está inicializada y corre `-i base` contra `postgres:5432`. La primera vez tarda. Esperá `HTTP service (werkzeug) running` y cortá los logs con Ctrl-C.

```bash
make odoo-verify
```

Avisa —no falla— si tu `ADDONS_BRANCH` no lleva la versión en el nombre: una rama de feature no la declara, y nada garantiza entonces que sea de la versión de la imagen.

---

## 7 · Backup — no corresponde

Development no respalda ni restaura: no trae la capa ni el perfil `restore`, y `make backup-run` falla a propósito. Lo que pierdas acá se rehace con `make nuke` y volver a empezar — es un entorno descartable por diseño.

---

## 8 · Monitoring — no corresponde

Sin Prometheus, Loki, Grafana ni Alloy. `make verify` marca la capa como omitida, no como fallada.

---

## 9 · Cierre

**Objetivo** — el stack convergido de una sola vez, y el aislamiento entre checkouts comprobado.

```bash
make up
```

```bash
make verify
```

```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:${HTTP_PORT}/web/login"
```

Tiene que dar `200`. Si esta es una shell nueva, cargá `.env` antes: `set -a; . ./.env; set +a`.

El aislamiento entre checkouts se comprueba una sola vez, con dos clonados y el primero levantado:

```bash
docker volume ls --format '{{.Name}}' | grep '^development-'
```

Tiene que haber un juego de volúmenes por nombre de proyecto —`development-sale_pgdata`, `development-accountant_pgdata`— y ninguno compartido. Si ves uno solo para los dos, los `COMPOSE_PROJECT_NAME` son iguales y las dos bases son la misma.

- [ ] `make verify` sale con exit `0`
- [ ] El login responde `200` en el puerto de este checkout
- [ ] Los volúmenes llevan el nombre de este checkout y no los comparte otro

De acá en más, el trabajo real sigue en [gestionar-modulo](../modulos/gestionar-modulo.md), y la validación de lo que hiciste en [validar-modulo-desarrollo](../validacion/validar-modulo-desarrollo.md).
