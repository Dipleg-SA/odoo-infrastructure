# Levantar staging

## Cuándo se usa

Puesta en marcha del segundo stack, en el mismo servidor que producción — necesario antes de validar cualquier cambio de módulo (ver [actualizar-modulo](../modulos/actualizar-modulo.md)) o de correr el simulacro semestral de restore. Asume producción ya operativa: ver [levantar-produccion](levantar-produccion.md) si todavía no lo está.

## Objetivo

Un segundo stack con su propio hostname, su propio certificado y su propio túnel, **sembrado con los datos de producción por un restore**. Sembrarlo y hacer el simulacro de restore son la misma operación — es la ocasión natural para el ejercicio que [`PRINCIPLES.md`](../../../PRINCIPLES.md) exige y que siempre se posterga.

Lleva proxy, borde, datos, aplicación y restore. **No lleva backups, observabilidad ni `dnsmasq`**: los tres son exclusivos de producción, y el `53` en `network_mode: host` no admite un segundo de ninguna forma.

## A mano

Un **Tunnel propio** en Zero Trust, no el de producción: el token es el que distingue a los dos stacks. Mismos campos que la fase 3 de [levantar-produccion](levantar-produccion.md), con el hostname de staging en Subdomain y en **Origin Server Name**, y `https://nginx:443` como Service.

Los 8 secrets se reparten en tres grupos, y solo el último es trabajo nuevo:

| Grupo | Cuáles | De dónde salen |
|---|---|---|
| Generados | `postgres_password` · `pgbouncer_credentials` · `odoo_admin_password` | `secrets-init` los saca de `openssl`; no se tocan |
| Copiados de producción | `restic_password` · `pgbackrest_r2_credentials` · `restic_r2_credentials` | Abren **su** repositorio: sin los mismos valores no hay nada que restaurar |
| De Cloudflare | `cloudflare_api_token` · `cloudflare_tunnel_token` | El API token puede ser el mismo de producción — es la misma zona. El del Tunnel es el del Tunnel nuevo |

En `.env`, ocho claves. Las de R2 y la stanza son **las de producción**, porque de ahí lee:

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | `staging` |
| `COMPOSE_FILE` | `compose.staging.yaml` |
| `PG_ARCHIVE_MODE` | `off` — la que no se puede olvidar, ver abajo |
| `PUBLIC_HOSTNAME` | El hostname de staging, distinto del de producción |
| `PGBACKREST_STANZA` · `R2_ENDPOINT` · `R2_BUCKET` | Los mismos valores que producción: es su repositorio el que se restaura |
| `ADDONS_BRANCH` | `<versión>-stag`, la rama de staging de los repos de addons |

Lo que las capas ausentes necesitarían —SMTP, alertas, retenciones— no está en la plantilla, y `LOCAL_IP` tampoco: staging no publica puertos, entra solo por el túnel. Si copiás una clave de más desde el `.env` de producción, dejala con valor o borrala: `make host-verify` marca las vacías.

> **`PG_ARCHIVE_MODE=off` es la línea que protege los backups de producción.** Staging apunta a la stanza de producción para poder restaurar; con el archivado prendido su propio Postgres le empuja WAL a ese repositorio y lo contamina desde el entorno que existe para romper cosas. Lo verifica `make db-verify`, que en un stack sin capa de backups **exige** que esté apagado.

## Comandos

```bash
echo "# 1 → Clonar en su propio directorio, fijado al último tag"
git clone "$REPO_URL" /srv/odoo-staging && cd /srv/odoo-staging
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

Checkout propio, como producción: `.env`, `secrets/`, `state/` y el árbol de addons son de este directorio y de ningún otro.

```bash
echo "# 2 → Config primero: el .env es lo que dice qué stack es este"
cp .env.stag.example .env
${EDITOR:-vi} .env    # las claves de la tabla de arriba; COMPOSE_FILE ya viene puesto
```

**El `.env` se completa antes de `secrets-init`, no después.** El script le pregunta a la composición cuáles secrets lleva este stack.

```bash
echo "# 3 → Los 8 secrets que declara este entrypoint"
make secrets-init
```

Cargá ahora los valores de la tabla de secrets, y después:

```bash
echo "# 4 → Permisos y grupo, y cargar .env en la shell"
sudo make secrets-perms
set -a; . ./.env; set +a
```

```bash
echo "# 5 → Certificado propio y árbol de addons de la rama -stag"
make cert-issue
make addons-sync
docker compose build
```

```bash
echo "# 6 → Sembrar la base desde el repositorio de producción"
make restore-up
docker compose exec restore-db pgbackrest restore --archive-mode=off
make restore-down
```

`--archive-mode=off` **no es opcional**: sin él el cluster restaurado hereda el `archive_command` del backup y empieza a empujar WAL a la stanza de producción.

```bash
echo "# 7 → Sembrar el filestore, del snapshot más nuevo que la base"
make restore-up
docker compose exec restore-files restic restore latest --target / --include /data/odoo
make restore-down
```

`--include /data/odoo` acota el restore a lo único que este contenedor monta. El orden importa y es el inverso al del backup: un filestore más nuevo que la base deja archivos huérfanos, inofensivos; uno más viejo deja filas apuntando a archivos que no existen.

```bash
echo "# 8 → Levantar el stack completo"
make up
```

## Verificación

```bash
echo "# 9 → Estado de las capas que este stack sí tiene"
make verify
```

Las capas ausentes salen como `--`, no en rojo. Lo que sí tiene que pasar es `archive_mode APAGADO`, el certificado vigente y las tres rutas de Odoo en nginx.
