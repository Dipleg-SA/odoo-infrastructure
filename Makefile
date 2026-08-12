.PHONY: up down logs ps config-init secrets-init secrets-perms secrets-check backup backup-full backup-check restore-up restore-down addons-sync addons odoo-install odoo-update odoo-modules require-modules require-backups require-restore verify verify-host verify-edge verify-db verify-odoo verify-backups verify-observability

# --- Inicialización de un deploy nuevo ---
# En orden: config-init, secrets-init, cargar los valores a mano, secrets-perms, secrets-check.

config-init:
	scripts/config-init.sh

secrets-init:
	scripts/secrets-init.sh

# --- Permisos de secrets ---
# Un solo script con el mapa de GIDs: --apply escribe (requiere root), --check valida.

secrets-perms:
	scripts/secrets-perms.sh --apply

secrets-check:
	scripts/secrets-perms.sh --check

# --- Verificación del deploy ---
# scripts/verify.sh es dueño único de qué se chequea y qué se espera; INSTALL.md solo
# nombra el target. verify (sin sufijo) dice en qué estado está el servidor entero.

verify:
	scripts/verify.sh all

verify-host verify-edge verify-db verify-odoo verify-backups verify-observability:
	scripts/verify.sh $(@:verify-%=%)

# --- Ciclo de vida del stack ---

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.Status}}"

# --- Addons ---
# sync clona/actualiza los dos árboles desde config/odoo/addons.txt; puro host, sin contenedores.

addons-sync:
	scripts/addons.sh sync

addons:
	scripts/addons.sh status

# --- Instalar/actualizar módulos ---
# El one-off corre -i/-u directo contra postgres:5432, no PgBouncer. El up -d va
# siempre, aunque el one-off falle: si no, un -i con error deja produccion abajo.
# --name: el servicio declara container_name, y sin un nombre propio el one-off
# chocaria contra el del servicio detenido. Dos stacks no pueden correr un
# one-off a la vez en el mismo host; falla ruidoso.

# MODULES es obligatorio: sin él, odoo consume --stop-after-init como nombre de módulo
# y deja producción detenida con el contenedor efímero sirviendo indefinidamente.
require-modules:
	@test -n "$(MODULES)" || { echo "falta MODULES — uso: make $(TARGET) MODULES=nombre_del_modulo" >&2; exit 2; }

odoo-install: TARGET=odoo-install
odoo-install: require-modules
	docker compose stop odoo
	@docker compose run --rm --name odoo-oneoff odoo -i $(MODULES) --stop-after-init; \
	  estado=$$?; \
	  docker compose up -d odoo; \
	  [ "$$estado" -eq 0 ] || echo "odoo-install: el -i falló (exit $$estado) — el servicio se levantó igual" >&2; \
	  exit "$$estado"

odoo-update: TARGET=odoo-update
odoo-update: require-modules
	docker compose stop odoo
	@docker compose run --rm --name odoo-oneoff odoo -u $(MODULES) --stop-after-init; \
	  estado=$$?; \
	  docker compose up -d odoo; \
	  [ "$$estado" -eq 0 ] || echo "odoo-update: el -u falló (exit $$estado) — el servicio se levantó igual" >&2; \
	  exit "$$estado"

odoo-modules:
	docker compose exec -T postgres psql -U odoo -d odoo -c "SELECT name, latest_version FROM ir_module_module WHERE state='installed' ORDER BY name"

# --- Guardas de capa ---
# Le preguntan a la composición, no a una variable: qué capas trae cada stack ya
# lo dice su entrypoint, y declararlo dos veces es una divergencia esperando.

require-backups:
	@docker compose config --services 2>/dev/null | grep -qx backup || \
	  { echo "este stack no incluye la capa de backups — es exclusiva de producción (revisar COMPOSE_FILE en .env)" >&2; exit 2; }

require-restore:
	@docker compose --profile restore config --services 2>/dev/null | grep -qx restore-db || \
	  { echo "este stack no incluye la capa de restore (revisar COMPOSE_FILE en .env)" >&2; exit 2; }

# --- Backups ---
# El restore no es un target — necesita un timestamp/snapshot según el incidente; ver docs/restore.md.

backup: require-backups
	scripts/backup.sh daily

backup-full: require-backups
	scripts/backup.sh monthly

backup-check: require-backups
	docker compose exec -T -u postgres postgres pgbackrest check
	docker compose exec -T backup restic check

# --- Restore ---
# Solo los dos servicios del perfil: `--profile restore down` a secas bajaría el stack entero.

restore-up: require-restore
	docker compose --profile restore up -d restore-db restore-files

restore-down: require-restore
	docker compose rm -sf restore-db restore-files
