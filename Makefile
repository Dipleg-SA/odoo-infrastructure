.PHONY: help up down logs ps nuke \
        cert-issue cert-renew secrets-init secrets-perms secrets-check \
        backup backup-full backup-check restore-up restore-down \
        addons-sync addons odoo-install odoo-update odoo-modules pydeps-check pydeps-sync \
        require-modules require-backups require-restore test verify host-verify \
        edge-up edge-down edge-restart edge-logs edge-ps edge-verify edge-nuke \
        db-up db-down db-restart db-logs db-ps db-verify db-nuke \
        odoo-up odoo-down odoo-restart odoo-logs odoo-ps odoo-verify odoo-nuke \
        backups-up backups-down backups-restart backups-logs backups-ps backups-verify backups-nuke \
        observability-up observability-down observability-restart observability-logs observability-ps observability-verify observability-nuke

.DEFAULT_GOAL := help

# --- Ayuda ---
# Sin target, o 'make help': lista los comandos agrupados por sección. Lee las
# cabeceras '# --- Título ---' y la anotación '##' de cada target, no mantiene nada aparte.

help:
	@awk 'BEGIN {FS = ":.*##"} \
	  /^# --- .* ---$$/ {t=$$0; sub(/^# --- /,"",t); sub(/ ---$$/,"",t); printf "\n\033[1m%s\033[0m\n", t} \
	  /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-23s\033[0m %s\n", $$1, substr($$0, index($$0,"##")+2)}' $(MAKEFILE_LIST)

# --- Inicialización de un deploy nuevo ---
# En orden: secrets-init, cargar los valores a mano, secrets-perms, secrets-check.
# Los tres scripts ya imprimen su propio ▶/✓/✗: el target no lo duplica.

secrets-init: ## Genera los secrets iniciales (valores dummy a completar a mano)
	scripts/secrets-init.sh

# --- Permisos de secrets ---
# Un solo script con el mapa de GIDs: --apply escribe (requiere root), --check valida.

secrets-perms: ## Aplica permisos de secrets (requiere root)
	scripts/secrets-perms.sh --apply

secrets-check: ## Verifica permisos de secrets
	scripts/secrets-perms.sh --check

# --- Certificados ---
# Emisión a mano la primera vez —nginx no arranca sin el archivo— y renovación
# por timer de systemd. DNS-01: no necesita que el borde esté arriba.

cert-issue: ## Emite el certificado inicial
	scripts/cert.sh issue

cert-renew: ## Renueva el certificado
	scripts/cert.sh renew

# --- Tests ---
# Los tres entrypoints, addons.sh y los derivadores de verify, cert y secrets. No
# levantan contenedores ni salen a la red: el estado de un deploy real es 'make verify'.

test: ## Corre los tests del repo, sin Docker ni red
	@. scripts/lib/ui.sh; total=0; ok=0; \
	  for t in tests/test_*.sh; do \
	    total=$$((total+1)); \
	    bash "$$t" && ok=$$((ok+1)); \
	  done; \
	  if [ "$$ok" -eq "$$total" ]; then ui_ok "tests listos — $$ok/$$total archivos ok"; \
	  else ui_bad "tests fallaron" "$$ok/$$total archivos ok"; fi; \
	  [ "$$ok" -eq "$$total" ]

# --- Verificación del deploy ---
# scripts/verify.sh es dueño único de qué se chequea y qué se espera; docs/runbooks/
# solo nombra el target. verify (sin sufijo) dice en qué estado está el servidor entero.

verify: ## Verifica el deploy completo — o <capa>-verify: host|edge|db|odoo|backups|observability
	scripts/verify.sh all

host-verify: ## Verifica la capa host (systemd, firewall, DHCP — sin contenedores)
	scripts/capa.sh host verify

# --- Ciclo de vida del stack, capa por capa ---
# Misma filosofía en las cinco: up/down/restart/logs/ps/verify/nuke, resueltos por
# scripts/capa.sh contra la composición real — un stack chico que no trae una capa
# no falla, la omite. up/down/logs/ps globales (abajo) siguen operando el stack entero.

edge-up: ## Levanta la capa edge (dnsmasq, nginx, cloudflared)
	scripts/capa.sh edge up

edge-down: ## Baja la capa edge
	scripts/capa.sh edge down

edge-restart: ## Reinicia la capa edge, sin tocar el resto del stack
	scripts/capa.sh edge restart

edge-logs: ## Sigue los logs de la capa edge
	scripts/capa.sh edge logs

edge-ps: ## Lista los contenedores de la capa edge
	scripts/capa.sh edge ps

edge-verify: ## Verifica la capa edge
	scripts/capa.sh edge verify

edge-nuke: ## Borra containers/imágenes/volúmenes de edge — confirmación: tipear 'nuke'
	scripts/capa.sh edge nuke

db-up: ## Levanta la capa db (postgres, pgbouncer)
	scripts/capa.sh db up

db-down: ## Baja la capa db
	scripts/capa.sh db down

db-restart: ## Reinicia la capa db, sin tocar el resto del stack
	scripts/capa.sh db restart

db-logs: ## Sigue los logs de la capa db
	scripts/capa.sh db logs

db-ps: ## Lista los contenedores de la capa db
	scripts/capa.sh db ps

db-verify: ## Verifica la capa db
	scripts/capa.sh db verify

db-nuke: ## Borra containers/imágenes/volúmenes de db — confirmación: tipear 'nuke'
	scripts/capa.sh db nuke

odoo-up: ## Levanta la capa odoo
	scripts/capa.sh odoo up

odoo-down: ## Baja la capa odoo
	scripts/capa.sh odoo down

odoo-restart: ## Reinicia la capa odoo, sin tocar el resto del stack
	scripts/capa.sh odoo restart

odoo-logs: ## Sigue los logs de la capa odoo
	scripts/capa.sh odoo logs

odoo-ps: ## Lista los contenedores de la capa odoo
	scripts/capa.sh odoo ps

odoo-verify: ## Verifica la capa odoo
	scripts/capa.sh odoo verify

odoo-nuke: ## Borra containers/imágenes/volúmenes de odoo — confirmación: tipear 'nuke'
	scripts/capa.sh odoo nuke

backups-up: ## Levanta la capa backups (restic; pgBackRest vive dentro de postgres)
	scripts/capa.sh backups up

backups-down: ## Baja la capa backups
	scripts/capa.sh backups down

backups-restart: ## Reinicia la capa backups, sin tocar el resto del stack
	scripts/capa.sh backups restart

backups-logs: ## Sigue los logs de la capa backups
	scripts/capa.sh backups logs

backups-ps: ## Lista los contenedores de la capa backups
	scripts/capa.sh backups ps

backups-verify: ## Verifica la capa backups
	scripts/capa.sh backups verify

backups-nuke: ## Borra containers/imágenes/volúmenes de backups — confirmación: tipear 'nuke'
	scripts/capa.sh backups nuke

observability-up: ## Levanta la capa observability (prometheus, loki, grafana, alloy)
	scripts/capa.sh observability up

observability-down: ## Baja la capa observability
	scripts/capa.sh observability down

observability-restart: ## Reinicia la capa observability, sin tocar el resto del stack
	scripts/capa.sh observability restart

observability-logs: ## Sigue los logs de la capa observability
	scripts/capa.sh observability logs

observability-ps: ## Lista los contenedores de la capa observability
	scripts/capa.sh observability ps

observability-verify: ## Verifica la capa observability
	scripts/capa.sh observability verify

observability-nuke: ## Borra containers/imágenes/volúmenes de observability — confirmación: tipear 'nuke'
	scripts/capa.sh observability nuke

# --- Ciclo de vida del stack completo ---

up: ## Levanta el stack completo
	@. scripts/lib/ui.sh; ui_run "up" docker compose up -d

down: ## Baja el stack completo
	@. scripts/lib/ui.sh; ui_run "down" docker compose down

logs: ## Sigue los logs de todos los servicios
	@. scripts/lib/ui.sh; ui_start "logs: siguiendo todo el stack (Ctrl-C para salir)"
	@docker compose logs -f

ps: ## Lista el estado de los contenedores, agrupado por capa
	scripts/capa.sh all ps

# --- Nuke ---
# El más destructivo del Makefile. Confirmación: tipear la palabra 'nuke', no Y/N.
# Nunca toca secrets/ ni .env — son credenciales de terceros, no derivables de nada.

nuke: ## Borra TODO: containers/imágenes/volúmenes del stack + addons/ + state/
	scripts/capa.sh all nuke

# --- Addons ---
# sync clona/actualiza los árboles desde addons/addons.txt; puro host, sin contenedores.

addons-sync: ## Clona/actualiza los addons desde addons/addons.txt
	scripts/addons.sh sync

addons: ## Muestra el estado de los addons
	@. scripts/lib/ui.sh; ui_run "addons" scripts/addons.sh status

# --- Dependencias Python de los addons ---
# check es puro host (corre en 'make test'); sync necesita Docker para resolver
# versión contra la imagen base. Ninguno de los dos rebuildea la imagen.

pydeps-check: ## Verifica que requirements.txt cubra las external_dependencies declaradas
	scripts/pydeps.sh check

pydeps-sync: ## Pinea en requirements.txt lo que declaren los addons y todavía falte
	scripts/pydeps.sh sync

# --- Instalar/actualizar módulos ---
# El one-off corre -i/-u directo contra postgres:5432, no PgBouncer. El up -d va
# siempre, aunque el one-off falle: si no, un -i con error deja produccion abajo.
# --name: el servicio declara container_name, y sin un nombre propio el one-off
# chocaria contra el del servicio detenido. Dos stacks no pueden correr un
# one-off a la vez en el mismo host; falla ruidoso.

# MODULES es obligatorio: sin él, odoo consume --stop-after-init como nombre de módulo
# y deja producción detenida con el contenedor efímero sirviendo indefinidamente.
require-modules:
	@. scripts/lib/ui.sh; test -n "$(MODULES)" || \
	  { ui_bad "falta MODULES" "uso: make $(TARGET) MODULES=nombre_del_modulo" >&2; exit 2; }

odoo-install: TARGET=odoo-install
odoo-install: require-modules ## Instala módulos — MODULES=nombre obligatorio
	@. scripts/lib/ui.sh; ui_start "odoo-install $(MODULES)"; \
	  docker compose stop odoo || exit $$?; \
	  docker compose run --rm --name odoo-oneoff odoo -i $(MODULES) --stop-after-init; \
	  estado=$$?; \
	  docker compose up -d odoo; \
	  if [ "$$estado" -eq 0 ]; then ui_ok "odoo-install listo"; \
	  else ui_bad "odoo-install falló" "exit $$estado — el servicio se levantó igual"; fi; \
	  exit "$$estado"

odoo-update: TARGET=odoo-update
odoo-update: require-modules ## Actualiza módulos — MODULES=nombre obligatorio
	@. scripts/lib/ui.sh; ui_start "odoo-update $(MODULES)"; \
	  docker compose stop odoo || exit $$?; \
	  docker compose run --rm --name odoo-oneoff odoo -u $(MODULES) --stop-after-init; \
	  estado=$$?; \
	  docker compose up -d odoo; \
	  if [ "$$estado" -eq 0 ]; then ui_ok "odoo-update listo"; \
	  else ui_bad "odoo-update falló" "exit $$estado — el servicio se levantó igual"; fi; \
	  exit "$$estado"

odoo-modules: ## Lista los módulos instalados en la base
	@salida=$$(docker compose exec -T postgres psql -U odoo -d odoo -A -F "$$(printf '\t')" --pset footer=off -c \
	  "SELECT name, latest_version FROM ir_module_module WHERE state='installed' ORDER BY name") || exit $$?; \
	  printf '%s\n' "$$salida" | column -t -s "$$(printf '\t')" \
	  | awk 'NR==1 {print; n=length($$0); s=""; for(i=0;i<n;i++) s=s "-"; print s; next} {print}'

# --- Guardas de capa ---
# Le preguntan a la composición, no a una variable: qué capas trae cada stack ya
# lo dice su entrypoint, y declararlo dos veces es una divergencia esperando.

require-backups:
	@. scripts/lib/ui.sh; docker compose config --services 2>/dev/null | grep -qx backup || \
	  { ui_bad "este stack no incluye la capa de backups" "es exclusiva de producción — revisar COMPOSE_FILE en .env" >&2; exit 2; }

require-restore:
	@. scripts/lib/ui.sh; docker compose --profile restore config --services 2>/dev/null | grep -qx restore-db || \
	  { ui_bad "este stack no incluye la capa de restore" "revisar COMPOSE_FILE en .env" >&2; exit 2; }

# --- Backups ---
# El restore no es un target — necesita un timestamp/snapshot según el incidente; ver docs/runbooks/backup-restore/.
# backup.sh ya imprime su propio ▶/✓/✗: el target no lo duplica.

backup: require-backups ## Corre el backup diario
	scripts/backup.sh daily

backup-full: require-backups ## Corre el backup mensual completo
	scripts/backup.sh monthly

backup-check: require-backups ## Verifica la integridad de los repositorios de backup
	@. scripts/lib/ui.sh; ui_run "backup-check" sh -c \
	  'docker compose exec -T -u postgres postgres pgbackrest check && docker compose exec -T backup restic check'

# --- Restore ---
# Solo los dos servicios del perfil: `--profile restore down` a secas bajaría el stack entero.

restore-up: require-restore ## Levanta los servicios de restore
	@. scripts/lib/ui.sh; ui_run "restore-up" docker compose --profile restore up -d restore-db restore-files

restore-down: require-restore ## Baja los servicios de restore
	@. scripts/lib/ui.sh; ui_run "restore-down" docker compose rm -sf restore-db restore-files
