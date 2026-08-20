# Levantar desarrollo

## Cuándo se usa

Vas a empezar a trabajar en una feature — un módulo nuevo o un cambio sobre uno existente — y necesitás tu propio entorno, aislado de cualquier otro checkout de desarrollo que tengas corriendo. Un checkout por feature, en tu máquina.

## Objetivo

Odoo sirviendo por nginx en loopback, sin túnel, sin certificados, sin backups, y **sin ningún valor que pegar a mano**: los tres secrets se generan.

nginx está presente aunque no haya TLS — es lo que hace honesto al `proxy_mode = True` de `odoo.conf`: sin nadie escribiendo `X-Forwarded-*`, Odoo confía en cabeceras que no existen, y esa diferencia con producción aparece justo en lo que es difícil de reproducir.

---

## Fase 1 — Repositorio

### Objetivo

Checkout propio por feature, con `.env` y los 3 secrets generados y con permisos. Nada levantado todavía.

### A mano

Nada que pegar. En `.env`, estas claves (`COMPOSE_FILE` ya viene puesto):

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | `development-<feature>`, **único por checkout** |
| `COMPOSE_FILE` | `compose.dev.yaml` |
| `PG_ARCHIVE_MODE` | `off` |
| `HTTP_PORT` | El puerto de loopback, distinto por checkout si vas a alternar |
| `ADDONS_BRANCH` | Tu rama de trabajo |

> **El nombre del proyecto es el único aislamiento entre dos checkouts de desarrollo.** De él salen los volúmenes: dos que lo compartan resuelven al mismo `pgdata`, y como corre uno a la vez no colisionan al arrancar — **se pisan los datos en silencio**. Si falta la clave, Compose usa el nombre del directorio, que ya es único; el caso peligroso es copiar el `.env` de un checkout a otro.

`NGINX_MODE` no se declara: `compose.dev.yaml` fija la plantilla sin TLS en el entrypoint.

### Comandos

```bash
echo "# 1 → Un directorio por feature, con su nombre adentro"
FEATURE='sale'
git clone "$REPO_URL" ~/odoo-development-$FEATURE && cd ~/odoo-development-$FEATURE
```

Acá **no** se fija a un tag: el checkout de desarrollo sigue la rama en la que estás trabajando. El `HEAD` detached es un guard-rail del servidor, donde nadie debería estar corrigiendo código.

```bash
echo "# 2 → Config: las claves de la tabla; COMPOSE_FILE ya viene puesto"
cp .env.dev.example .env
${EDITOR:-vi} .env
```

**Antes de `secrets-init`, no después.** El `COMPOSE_PROJECT_NAME` hay que editarlo igual aunque la plantilla ya traiga `COMPOSE_FILE`: el placeholder es el mismo para todo checkout que no lo cambie, y de ahí salen los volúmenes.

```bash
echo "# 3 → Los 3 secrets, todos generados"
make secrets-init
sudo make secrets-perms
```

`secrets-init` no imprime ningún pendiente: los tres salen de `openssl`.

```bash
echo "# 4 → Cargar .env en la shell"
set -a; . ./.env; set +a
```

### Verificación

Ninguna aislada: los tres secrets se generan solos y no hay ninguna cuenta externa que confirmar todavía. Se verifica en conjunto en la fase 3.

---

## Fase 2 — Addons

### Objetivo

El árbol de addons de tu rama en disco y la imagen de Odoo construida.

### A mano

Ninguno. Si todavía no declaraste ningún repo propio en `addons/addons.txt`, ver [crear-fork](../modulos/crear-fork.md).

### Comandos

```bash
echo "# 1 → Árbol de addons y build de la imagen"
make addons-sync
docker compose build
```

### Verificación

```bash
echo "# 2 → Estado de cada worktree"
make addons
```

Encabeza con la rama declarada y sigue con una fila por repo del manifiesto, todas en `limpio`.

---

## Fase 3 — Aplicación

### Objetivo

Odoo sirviendo por nginx en loopback, con el aislamiento entre checkouts comprobado.

### A mano

Ninguno.

### Comandos

```bash
echo "# 1 → Levantar"
make up
```

La base arranca vacía: el entrypoint detecta que no está inicializada y corre `-i base` contra `postgres:5432`, no contra PgBouncer. La primera vez tarda.

### Verificación

```bash
echo "# 2 → Estado, y el sitio por el proxy"
set -a; . ./.env; set +a    # por si esta es una shell nueva desde la fase 1
make verify
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:${HTTP_PORT:-8080}/web/login"
```

Tiene que dar `200`. `make verify` omite el certificado, el `server_name` y el 443 —derivados de que este stack sirve en texto plano—, y avisa en vez de fallar si tu `ADDONS_BRANCH` no lleva la versión en el nombre.

El aislamiento entre checkouts se comprueba una sola vez, con dos clonados:

```bash
echo "# 3 → Desde el segundo checkout, con el primero levantado"
docker volume ls --format '{{.Name}}' | grep '^development-'
```

Tiene que haber un juego de volúmenes por nombre de proyecto —`development-sale_pgdata`, `development-accountant_pgdata`— y ninguno compartido. Si ves uno solo para los dos, los `COMPOSE_PROJECT_NAME` son iguales y las dos bases son la misma.

---

De acá en más, el trabajo real sigue en [crear-modulo](../modulos/crear-modulo.md) o [actualizar-modulo](../modulos/actualizar-modulo.md), y la validación de lo que hiciste en [validar-modulo-desarrollo](../validacion/validar-modulo-desarrollo.md).
