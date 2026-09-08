# --- Shell de las recetas ---
# Sin esto Make usa /bin/sh (dash en Debian/Ubuntu), que no entiende el $'\033[...'
# de ui.sh y lo imprime literal en vez de interpretarlo como color.

SHELL := bash

include .make/main.mk

.PHONY: help up down logs ps nuke reset build \
        secrets-init secrets-perms secrets-check config-init dev-workspace \
        host-init host-verify up-timers down-timers notify-test monitoring-role \
        cert-issue cert-renew \
        backup-run backup-integrity restore \
        repo-sync repo-status repo-branch addons-install addons-update addons-modules addons-deps \
        require-modules require-backups require-restore require-root require-not-production test verify \
        $(foreach s,$(STACKS),$(s)-up $(s)-down $(s)-restart $(s)-logs $(s)-ps $(s)-verify) \
        $(foreach s,$(STACKS_ONESHOT),$(s)-logs $(s)-ps $(s)-verify)
.DEFAULT_GOAL := help

# --- Ayuda ---
# Sin target, o 'make help': lista los comandos agrupados por sección. Lee las
# cabeceras '# --- Título ---' y la anotación '##' de cada target, no mantiene nada aparte.

help:
	@awk -v stacks="$(STACKS)" -v oneshot="$(STACKS_ONESHOT)" \
	     -v m_borde="$(MACRO_BORDE)" -v m_datos="$(MACRO_DATOS)" \
	     -v m_app="$(MACRO_APP)" -v m_obs="$(MACRO_OBS)" \
	     -f .make/help.awk $(MAKEFILE_LIST)

# ============================================================
# HOST — comandos que no son de un stack puntual
# ============================================================

# --- [HOST] Secrets y configuración ---
# Bootstrap de un deploy nuevo: secrets-init y config-init, cargar los valores a
# mano, secrets-perms, secrets-check. Los scripts ya imprimen su ▶/✓/✗ propio.

secrets-init: ## Genera los secrets iniciales (valores dummy a completar a mano)
	scripts/secrets-init.sh

# Un solo script con el mapa de GIDs: --apply escribe (requiere root), --check valida.
secrets-perms: ## Aplica permisos de secrets (requiere root)
	scripts/secrets-perms.sh --apply

secrets-check: ## Verifica permisos de secrets
	scripts/secrets-perms.sh --check

# Mismo mecanismo que secrets-init, pero para los .conf/.ini/.yaml gitignoreados de
# stacks/*/config/ y addons/: un cp idempotente desde el .example de cada uno.
config-init: ## Bootstrapea los config reales desde su .example
	scripts/config-init.sh

# --- [HOST] Workspace de VS Code ---
# Un folder por tipo de addon + la raíz de infra, generado desde .env — para
# no mezclar edición de módulos con archivos de infraestructura en el mismo árbol.

dev-workspace: ## Genera <entorno>.code-workspace: un folder por tipo de addon + infra
	scripts/vscode-workspace.sh

# --- Config de sistema operativo ---
# Lo único del repo que se instala FUERA del checkout, y por eso pide root: la
# rotación de logs del daemon y las units de systemd de este stack.

require-root:
	@. scripts/lib/ui.sh; [ "$$(id -u)" -eq 0 ] || \
	  { ui_bad "$(TARGET) necesita root" "sudo make $(TARGET)" >&2; exit 2; }

host-init: TARGET=host-init
host-init: require-root ## Aplica la rotación de logs del daemon (requiere root)
	@. scripts/lib/ui.sh; \
	  if [ -e /etc/docker/daemon.json ] && ! cmp -s host/daemon.json /etc/docker/daemon.json; then \
	    MAX_SIZE=$$(grep -o '"max-size"[^,}]*' host/daemon.json); \
	    MAX_FILE=$$(grep -o '"max-file"[^,}]*' host/daemon.json); \
	    if grep -qF "$$MAX_SIZE" /etc/docker/daemon.json && grep -qF "$$MAX_FILE" /etc/docker/daemon.json; then \
	      ui_skip "/etc/docker/daemon.json ya rota logs igual que el repo (difiere solo en formato o en claves propias del host)"; \
	      exit 0; \
	    fi; \
	    ui_bad "/etc/docker/daemon.json ya existe y no rota logs como el repo" \
	      "el cp borraría las claves propias del host (data-root, insecure-registries, runtimes) — fusionar a mano el bloque log-driver/log-opts de host/daemon.json. Diferencia (izquierda: tuyo, derecha: repo):" >&2; \
	    diff -u /etc/docker/daemon.json host/daemon.json >&2 || true; \
	    exit 2; \
	  fi; \
	  ui_run "host-init" sh -c \
	    'cp host/daemon.json /etc/docker/daemon.json && systemctl restart docker'

up-timers: ## Instala y activa las units de systemd de este stack (requiere root)
	scripts/timers.sh install

down-timers: ## Desinstala las units de systemd de este checkout (requiere root)
	scripts/timers.sh remove

notify-test: TARGET=notify-test
notify-test: require-root ## Dispara el aviso de fallo de punta a punta (requiere root)
	@. scripts/lib/ui.sh; unidad="$$(scripts/timers.sh notify)prueba.service"; \
	  ui_start "notify-test: $$unidad"; \
	  if ! systemctl start "$$unidad"; then \
	    ui_bad "notify-test falló" "systemctl no pudo arrancar $$unidad — ¿corriste 'sudo make up-timers'? Últimas líneas del journal:"; \
	    journalctl -u "$$unidad" -n 20 --no-pager; exit 1; \
	  fi; \
	  resultado=$$(systemctl show -p Result --value "$$unidad"); \
	  if [ "$$resultado" = "success" ]; then ui_ok "notify-test listo — Result=success, ahora confirmá que el mail llegó"; \
	  else ui_bad "notify-test falló" "Result=$$resultado — últimas líneas del journal:"; \
	    journalctl -u "$$unidad" -n 20 --no-pager; exit 1; fi

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
# Cada stacks/<nombre>/verify.sh es dueño de qué se espera de él; el orquestador solo
# decide cuáles corre. Los runbooks nombran el target, nunca los valores esperados.

verify: ## Verifica el deploy completo — o <stack>-verify para uno solo
	scripts/verify-stacks.sh all

host-verify: ## Verifica los prerrequisitos del SO (systemd, rotación de logs, secrets)
	scripts/verify-host.sh

# --- Ciclo de vida del stack completo ---

up: ## Levanta el stack completo
	@. scripts/ui/components.sh; ui_section "up: levantando el stack completo"; ui_run "up" docker compose up -d

down: ## Baja el stack completo
	@. scripts/lib/ui.sh; ui_run "down" docker compose down

logs: ## Sigue los logs de todos los servicios
	@. scripts/ui/components.sh; ui_section "logs: siguiendo todo el stack (Ctrl-C para salir)"; docker compose logs -f

ps: ## Lista el estado de los contenedores
	@. scripts/ui/components.sh; salida=$$(docker compose ps --format "{{.Name}}$$(printf '\t'){{.Status}}$$(printf '\t'){{.Ports}}") || exit $$?; printf '%s\n' "$$salida" | ui_ps_table

# nuke: el más destructivo del Makefile — confirmación tipeando la palabra, no Y/N,
# y nunca toca secrets/ ni .env. reset es lo mismo pero solo los volúmenes: containers,
# imágenes y addons/ quedan como están, así que el up posterior no rebuildea nada.

nuke: ## Borra TODO: containers/imágenes/volúmenes del stack + addons/ + state/
	@. scripts/lib/ui.sh; \
	  ui_warn "esto borra los datos de este stack" \
	    "volúmenes, imágenes propias, addons/ y state/ — secrets/ y .env NO se tocan"; \
	  ui_confirm nuke || exit 1; \
	  ui_run "nuke" sh -c 'docker compose down -v --rmi local --remove-orphans && \
	    rm -rf addons/.repos addons/*/*/ state/textfile/*.prom state/meta/*.txt'

# Mismo indicador que require-backups, leído al revés: backup sin profiles: solo
# está en producción (en staging tiene profiles: [restore]; en development no está).
require-not-production:
	@. scripts/lib/ui.sh; docker compose config --services 2>/dev/null | grep -qx backup && \
	  { ui_bad "$(TARGET) no corre en producción" "este checkout tiene la capa de backups activa sin profiles: — es producción" >&2; exit 2; } || true

reset: TARGET=reset
reset: require-not-production ## Borra los datos (volúmenes) y vuelve a levantar limpio — nunca en producción
	@. scripts/lib/ui.sh; \
	  ui_warn "esto borra los datos de este stack" \
	    "volúmenes (base, filestore, dumps) — containers, imágenes y addons/ quedan igual"; \
	  ui_confirm reset || exit 1; \
	  ui_run "reset" sh -c 'docker compose down -v && docker compose up -d'

# --- [STACK:repo] Árbol de addons ---
# sync clona/actualiza los árboles desde addons/addons.txt; puro host, sin contenedores.

repo-sync: ## Clona/actualiza los addons desde addons/addons.txt
	scripts/addons.sh sync

repo-status: ## Muestra el estado de los addons
	@. scripts/lib/ui.sh; ui_run "repo-status" scripts/addons.sh status

# --- [STACK:repo] Rama nueva de checkout de desarrollo ---
# Antes del primer repo-sync de un checkout: crea ADDONS_BRANCH en origin de
# cada repo, partiendo de la versión del Dockerfile. Falla si ya existe o si
# ADDONS_BRANCH no se redeclaró en .env todavía.

repo-branch: ## Crea ADDONS_BRANCH (rama de feature en .env) en origin de cada addon
	scripts/addons.sh branch

# --- Imágenes propias ---
# Todo stack construye la suya, aunque el Dockerfile sea un FROM pineado y nada más.
# El build de odoo no clona nada: los addons entran por bind-mount, no por capa.

build: ## Construye las imágenes propias de este stack
	@. scripts/lib/ui.sh; ui_run "build" docker compose build

# --- [STACK:addons] Dependencias Python ---
# check es puro host (corre en 'make test'); sync necesita Docker para resolver
# versión contra la imagen base. Ninguno de los dos rebuildea la imagen.
# El '-' en check: Make aborta el target ante cualquier línea que falle, y un
# check con faltantes es justo el caso en el que sync tiene que correr igual.

addons-deps: ## Verifica requirements.txt contra las external_dependencies y pinea lo que falte
	-scripts/pydeps.sh check
	scripts/pydeps.sh sync

# ============================================================
# STACKS — sexteto genérico + lo puntual de cada uno, agrupado
# ============================================================

# --- [SEXTETO] Ciclo de vida, stack por stack ---
# Sexteto (o trío, para STACKS_ONESHOT) generado en .make/; help.awk sintetiza la descripción.

# --- [STACK:addons] Instalar/actualizar módulos ---
# El one-off corre -i/-u con la conexión explícita a postgres:5432. El up -d va
# siempre, aunque el one-off falle: si no, un -i con error deja produccion abajo.
# --name: el servicio declara container_name, y sin un nombre propio el one-off
# chocaria contra el del servicio detenido. Dos stacks no pueden correr un
# one-off a la vez en el mismo host; falla ruidoso.

# MODULES es obligatorio: sin él, odoo consume --stop-after-init como nombre de módulo
# y deja producción detenida con el contenedor efímero sirviendo indefinidamente.
require-modules:
	@. scripts/lib/ui.sh; test -n "$(MODULES)" || \
	  { ui_bad "falta MODULES" "uso: make $(TARGET) MODULES=nombre_del_modulo" >&2; exit 2; }

addons-install: TARGET=addons-install
addons-install: require-modules ## Instala módulos — MODULES=nombre obligatorio
	@. scripts/lib/ui.sh; ui_start "addons-install $(MODULES)"; \
	  docker compose stop odoo || exit $$?; \
	  docker compose run --rm --name odoo-oneoff odoo -i $(MODULES) --stop-after-init; \
	  estado=$$?; \
	  docker compose up -d odoo; \
	  if [ "$$estado" -eq 0 ]; then ui_ok "addons-install listo"; \
	  else ui_bad "addons-install falló" "exit $$estado — el servicio se levantó igual"; fi; \
	  exit "$$estado"

addons-update: TARGET=addons-update
addons-update: require-modules ## Actualiza módulos — MODULES=nombre obligatorio
	@. scripts/lib/ui.sh; ui_start "addons-update $(MODULES)"; \
	  docker compose stop odoo || exit $$?; \
	  docker compose run --rm --name odoo-oneoff odoo -u $(MODULES) --stop-after-init; \
	  estado=$$?; \
	  docker compose up -d odoo; \
	  if [ "$$estado" -eq 0 ]; then ui_ok "addons-update listo"; \
	  else ui_bad "addons-update falló" "exit $$estado — el servicio se levantó igual"; fi; \
	  exit "$$estado"

addons-modules: ## Lista los módulos instalados en la base
	@salida=$$(docker compose exec -T postgres psql -U odoo -d odoo -A -F "$$(printf '\t')" --pset footer=off -c \
	  "SELECT name, latest_version FROM ir_module_module WHERE state='installed' ORDER BY name") || exit $$?; \
	  printf '%s\n' "$$salida" | column -t -s "$$(printf '\t')" \
	  | awk 'NR==1 {print; n=length($$0); s=""; for(i=0;i<n;i++) s=s "-"; print s; next} {print}'

# --- [STACK:backup] Operación ---
# El diario respalda y purga; el check verifica integridad del repositorio. No hay
# 'full': en restic todo snapshot es completo y la retención GFS la hace forget.

# Le pregunta a la composición, no a una variable: qué capas trae cada stack ya
# lo dice su entrypoint, y declararlo dos veces es una divergencia esperando.
require-backups:
	@. scripts/lib/ui.sh; docker compose config --services 2>/dev/null | grep -qx backup || \
	  { ui_bad "este stack no incluye la capa de backups" "es exclusiva de producción — revisar COMPOSE_FILE en .env" >&2; exit 2; }

# Dos guardas y no una: respaldar es de producción, restaurar es de los dos entornos.
# La diferencia sale de la composición, no de una lista — el entrypoint de prueba le
# pone profiles: [restore] al servicio backup, así que queda fuera del default (y de
# lo que ve timers.sh) pero sigue alcanzable para restaurar.
require-restore:
	@. scripts/lib/ui.sh; docker compose --profile restore config --services 2>/dev/null | grep -qx backup || \
	  { ui_bad "este stack no incluye la capa de restore" "revisar COMPOSE_FILE en .env" >&2; exit 2; }

backup-run: require-backups ## Corre el backup diario (dump + filestore en un snapshot)
	stacks/backup/scripts/backup.sh daily

backup-integrity: require-backups ## Verifica la integridad del repositorio (restic check)
	stacks/backup/scripts/backup.sh check

restore: require-restore ## Restaura filestore y base desde un snapshot — SNAPSHOT=latest
	stacks/backup/scripts/restore.sh $(or $(SNAPSHOT),latest)

# --- [STACK:alloy] Rol de monitoreo ---
# No sale de la imagen: lo crea el operador contra la base ya viva. DROP+CREATE lo
# hace repetible, y con eso sirve también para rotar la clave.

monitoring-role: ## Crea (o rota) el rol de solo lectura que scrapea Postgres
	stacks/alloy/scripts/monitoring-role.sh

# --- [STACK:certbot] Certificados ---
# Emisión a mano la primera vez, renovación por timer — nunca con up/down/restart.

cert-issue: ## Emite el certificado inicial
	stacks/certbot/scripts/cert.sh issue

cert-renew: ## Renueva el certificado
	stacks/certbot/scripts/cert.sh renew
