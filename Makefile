# --- Shell de las recetas ---
# Sin esto Make usa /bin/sh (dash en Debian/Ubuntu), que no entiende el $'\033[...'
# de ui.sh y lo imprime literal en vez de interpretarlo como color.

SHELL := bash

# Despacho de Compose
# Todos los verbos usan el contexto centralizado del runtime seleccionado.
CONTEXTO_COMPOSE := scripts/lib/contexto.sh compose

include .make/main.mk

.PHONY: help up down logs ps nuke reset build require-odoo-image promotion-verify \
        secrets-init secrets-perms secrets-check config-init workspace \
        addons-runtime-init \
        odoo-report-config \
        host-init host-verify up-timers down-timers notify-test monitoring-role \
        cert-issue cert-renew \
        backup-run backup-integrity restore integrity-check \
        repo-sync repo-status addons-install addons-update addons-uninstall addons-modules addons-deps \
        require-entorno require-modules require-backups require-restore require-root require-systemd require-not-production test test-smoke verify \
        $(foreach s,$(STACKS),$(s)-up $(s)-down $(s)-restart $(s)-logs $(s)-ps $(s)-verify) \
        $(foreach s,$(STACKS_ONESHOT),$(s)-logs $(s)-ps $(s)-verify)
.DEFAULT_GOAL := help

# Selector de operaciones
# Todos los comandos del runtime validan el entorno antes de ejecutar sus recetas.
RUNTIME_TARGETS := secrets-init secrets-perms secrets-check config-init workspace odoo-report-config \
                   host-verify up-timers down-timers notify-test monitoring-role cert-issue cert-renew \
                   backup-run backup-integrity restore repo-sync repo-status \
                   integrity-check \
                   addons-install addons-update addons-uninstall addons-modules addons-deps \
                   require-odoo-image require-backups require-restore require-not-production verify \
                   up down logs ps nuke reset build promotion-verify
RUNTIME_TARGETS += $(foreach s,$(STACKS),$(s)-up $(s)-down $(s)-restart $(s)-logs $(s)-ps $(s)-verify)
RUNTIME_TARGETS += $(foreach s,$(STACKS_ONESHOT),$(s)-logs $(s)-ps $(s)-verify)
$(RUNTIME_TARGETS): require-entorno

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
# stacks/*/config/: un cp idempotente desde el .example de cada uno.
config-init: ## Bootstrapea los config reales desde su .example
	scripts/config-init.sh

# --- [HOST] Directorios de addons ---
# Prepara los binds escribibles del webhook antes de que Compose pueda tocarlos.

addons-runtime-init: ## Inicializa los árboles custom de los tres entornos
	scripts/addons-runtime.sh init

addons-webhook-up: addons-runtime-init

odoo-report-config: ## Configura las URLs pública e interna de los reportes Odoo
	scripts/odoo-report-config.sh


# --- [HOST] Workspace de VS Code ---
# Expone los candidatos operativos del entorno y la infraestructura sin presentar
# el runtime derivado como un checkout de desarrollo de módulos.

workspace: ## Genera el workspace del entorno y sus candidatos
	scripts/vscode-workspace.sh

# Selector de runtime
# Falla antes de Docker si falta el entorno, su composición o su archivo privado.
require-entorno:
	scripts/lib/contexto.sh validar

# --- Config de sistema operativo ---
# Lo único del repo que se instala FUERA del checkout, y por eso pide root: la
# rotación de logs del daemon y las units de systemd de este stack.

require-root:
	@. scripts/lib/ui.sh; [ "$$(id -u)" -eq 0 ] || \
	  { ui_bad "$(TARGET) necesita root" "sudo make $(TARGET)" >&2; exit 2; }

# host-init escribe la configuración de Docker Engine y lo reinicia con systemctl.
# Comprobar el sistema primero evita sugerir ese comando para Docker Desktop.
require-systemd:
	@. scripts/lib/ui.sh; { [ "$$(uname -s)" = Linux ] && command -v systemctl >/dev/null 2>&1; } || \
	  { ui_bad "$(TARGET) requiere Linux con systemd" "Docker Desktop se configura desde Settings > Docker Engine" >&2; exit 2; }

host-init: TARGET=host-init
host-init: require-systemd require-root ## Aplica la rotación de logs del daemon en Linux (requiere root)
	@. scripts/lib/ui.sh; \
	  if ! python3 -c 'import json; json.load(open("host/daemon.json"))' >/dev/null 2>&1; then \
	    ui_bad "host/daemon.json inválido" "el contrato versionado no es JSON válido" >&2; exit 2; \
	  fi; \
	  if [ -e /etc/docker/daemon.json ] && ! cmp -s host/daemon.json /etc/docker/daemon.json; then \
	    MAX_SIZE=$$(grep -o '"max-size"[^,}]*' host/daemon.json); \
	    MAX_FILE=$$(grep -o '"max-file"[^,}]*' host/daemon.json); \
	    LOG_DRIVER=$$(grep -o '"log-driver"[^,}]*' host/daemon.json); \
	    if grep -qF "$$LOG_DRIVER" /etc/docker/daemon.json && grep -qF "$$MAX_SIZE" /etc/docker/daemon.json && grep -qF "$$MAX_FILE" /etc/docker/daemon.json; then \
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

test-smoke: ## Valida builds y configuraciones con Docker real (requiere daemon y red)
	@DOCKER_SMOKE=1 bash tests/test_docker_smoke.sh

# --- Verificación del deploy ---
# Cada stacks/<nombre>/verify.sh es dueño de qué se espera de él; el orquestador solo
# decide cuáles corre. Los runbooks nombran el target, nunca los valores esperados.

verify: ## Verifica el deploy completo — o <stack>-verify para uno solo
	scripts/verify-stacks.sh all

host-verify: ## Verifica los prerrequisitos del SO (systemd, rotación de logs, secrets)
	scripts/verify-host.sh

# --- Ciclo de vida del stack completo ---

up: ## Levanta el stack completo
	@. scripts/ui/components.sh; ui_section "up: levantando el stack completo"; scripts/odoo-lifecycle.sh stack-up
	@$(MAKE) odoo-report-config

down: ## Baja el stack completo
	@. scripts/lib/ui.sh; ui_run "down" $(CONTEXTO_COMPOSE) down

logs: ## Sigue los logs de todos los servicios
	@. scripts/ui/components.sh; ui_section "logs: siguiendo todo el stack (Ctrl-C para salir)"; $(CONTEXTO_COMPOSE) logs -f

ps: ## Lista el estado de los contenedores
	@. scripts/ui/components.sh; salida=$$($(CONTEXTO_COMPOSE) ps --format "{{.Name}}$$(printf '\t'){{.Status}}$$(printf '\t'){{.Ports}}") || exit $$?; printf '%s\n' "$$salida" | ui_ps_table

# nuke exige escribir su nombre y elimina volúmenes, imágenes propias y estado generado del entorno seleccionado.
# reset exige confirmación y recrea solo volúmenes; ambos conservan configs y secretos.

nuke: ## Borra containers/imágenes/volúmenes del stack y estado generado del entorno seleccionado
	@. scripts/lib/ui.sh; \
	  ui_warn "esto borra los datos de este stack" \
	    "volúmenes, imágenes propias y estado generado de runtime/ — configs y secretos quedan"; \
	  ui_confirm nuke || exit 1; \
	  ui_run "nuke" env ENTORNO="$$ENTORNO" bash -c '$(CONTEXTO_COMPOSE) down -v --rmi local --remove-orphans && \
	    rm -rf runtime/$${ENTORNO}/addons runtime/addons/builds/$${ENTORNO} \
	      runtime/$${ENTORNO}/state/*'

# Mismo indicador que require-backups, leído al revés: backup sin profiles: solo
# está en producción (en staging tiene profiles: [restore]; en desarrollo no está).
require-not-production:
	@. scripts/lib/ui.sh; servicios=$$($(CONTEXTO_COMPOSE) config --services 2>/dev/null) || exit $$?; \
	  if grep -qx backup <<< "$$servicios"; then \
	    ui_bad "$(TARGET) no corre en producción" "este runtime tiene la capa de backups activa sin profiles: — es producción" >&2; exit 2; \
	  fi

reset: TARGET=reset
reset: require-not-production ## Borra los datos (volúmenes) y vuelve a levantar limpio — nunca en producción
	@. scripts/lib/ui.sh; \
	  ui_warn "esto borra los datos de este stack" \
	    "volúmenes (base, filestore, dumps) — containers, imágenes y runtime/addons/ quedan igual"; \
	  ui_confirm reset || exit 1; \
	  ui_run "reset" bash -c '$(CONTEXTO_COMPOSE) down -v && $(CONTEXTO_COMPOSE) up -d'
	@$(MAKE) odoo-report-config

# --- [STACK:addons] Repositorios de dominio ---
# Sync actualiza el clon bare y publica el candidato del entorno seleccionado.

repo-sync: ## Sincroniza los candidatos declarados en runtime/addons/catalogo.txt
	scripts/addons.sh sync

repo-status: ## Muestra el estado de los addons
	@. scripts/lib/ui.sh; ui_run "repo-status" scripts/addons.sh status

integrity-check: ## Comprueba adjuntos de Odoo contra el filestore
	scripts/integrity-check.sh "$(DB)"

# --- Imágenes propias ---
# Todo stack construye la suya, aunque el Dockerfile sea un FROM pineado y nada más.
# El build de Odoo resuelve dependencias desde una fotografía, pero no copia addons.

# --- Construcción de imágenes propias ---
# Odoo se fotografía y las imágenes auxiliares se construyen desde sus stacks.

build: ## Construye las imágenes propias del runtime
	scripts/build-odoo-image.sh
	@. scripts/lib/ui.sh; ui_run "construir imágenes auxiliares" $(CONTEXTO_COMPOSE) build postgres nginx

# Selector único de Odoo
# Impide levantar el runtime con un tag inicial, flotante o inexistente.
require-odoo-image: require-entorno
	@. scripts/lib/ui.sh; \
	  . scripts/lib/contexto.sh; \
	  contexto_iniciar || exit $$?; \
	  image="$${ODOO_IMAGE:-}"; \
	if [[ ! "$$image" =~ ^local/odoo:[0-9]+([.][0-9]+)*-(desarrollo|staging|produccion)-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}$$ ]]; then \
	  ui_bad "ODOO_IMAGE inválida" "ejecutá ENTORNO=$$ENTORNO make build antes de levantar el runtime" >&2; exit 2; \
	fi; \
	if ! docker image inspect "$$image" >/dev/null 2>&1; then \
	  ui_bad "falta la imagen Odoo" "no existe $$image — ejecutá ENTORNO=$$ENTORNO make build" >&2; exit 2; \
	fi

up: require-odoo-image
odoo-up: require-odoo-image
odoo-restart: require-odoo-image

promotion-verify: ## Verifica que producción equivale a staging validado antes del build
	scripts/promotion-verify.sh

# --- [STACK:addons] Dependencias Python ---
# check es puro host; compile fija referencias Git y genera el lock operativo.
# El build repite ambos contra su propia fotografía antes de invocar Docker.

addons-deps: ## Valida requisitos de addons y compila el lock del entorno
	@. scripts/lib/contexto.sh; contexto_iniciar; . scripts/lib/candidate-lock.sh; \
	  candidate_lock_run "$$ENTORNO" -- env CANDIDATE_LOCK_HELD=1 bash -c \
	  'scripts/addons-runtime.sh validate && scripts/pydeps.sh check && scripts/pydeps.sh compile'

# ============================================================
# STACKS — sexteto genérico + lo puntual de cada uno, agrupado
# ============================================================

# --- [SEXTETO] Ciclo de vida, stack por stack ---
# Sexteto (o trío, para STACKS_ONESHOT) generado en .make/; help.awk sintetiza la descripción.

# --- [STACK:addons] Operar módulos ---
# Los tres targets delegan en el mismo runner y en la API ORM de Odoo. El up -d va
# siempre, aunque el one-off falle: una operación con error no deja producción abajo.
# El runner serializa operaciones con un lock de host. --name: el servicio declara
# container_name, y sin un nombre propio el one-off chocaría contra el del servicio
# detenido; también protege frente a un contenedor huérfano tras un corte.

# MODULES es obligatorio: evita ejecutar una operación ambigua sobre la base.
require-modules:
	@. scripts/lib/ui.sh; test -n "$(MODULES)" || \
	  { ui_bad "falta MODULES" "uso: make $(TARGET) MODULES=nombre_del_modulo" >&2; exit 2; }

addons-install: TARGET=addons-install
addons-install: require-modules ## Instala módulos — MODULES=nombre obligatorio
	scripts/odoo-module-operation.sh install

addons-update: TARGET=addons-update
addons-update: require-modules ## Actualiza módulos — MODULES=nombre obligatorio
	scripts/odoo-module-operation.sh update

addons-uninstall: TARGET=addons-uninstall
addons-uninstall: require-modules ## Desinstala módulos — MODULES=nombre obligatorio
	scripts/odoo-module-operation.sh uninstall

addons-modules: ## Lista los módulos instalados en la base
	@salida=$$($(CONTEXTO_COMPOSE) exec -T postgres psql -U odoo -d odoo -A -F "$$(printf '\t')" --pset footer=off -c \
	  "SELECT name, latest_version FROM ir_module_module WHERE state='installed' ORDER BY name") || exit $$?; \
	  printf '%s\n' "$$salida" | column -t -s "$$(printf '\t')" \
	  | awk 'NR==1 {print; n=length($$0); s=""; for(i=0;i<n;i++) s=s "-"; print s; next} {print}'

# --- [STACK:backup] Operación ---
# El diario respalda y purga; el check verifica integridad del repositorio. No hay
# 'full': en restic todo snapshot es completo y la retención GFS la hace forget.

# Le pregunta a la composición, no a una variable: qué capas trae cada stack ya
# lo dice su entrypoint, y declararlo dos veces es una divergencia esperando.
require-backups:
	@. scripts/lib/ui.sh; servicios=$$($(CONTEXTO_COMPOSE) config --services 2>/dev/null) || exit $$?; \
	  grep -qx backup <<< "$$servicios" || \
	    { ui_bad "este runtime no incluye la capa de backups" "es exclusiva de producción" >&2; exit 2; }

# Dos guardas y no una: respaldar es de producción, restaurar es de los dos entornos.
# La diferencia sale de la composición, no de una lista — el entrypoint de staging le
# pone profiles: [restore] al servicio backup, fuera del default y de lo que ve timers.sh.
require-restore:
	@. scripts/lib/ui.sh; servicios=$$(scripts/lib/contexto.sh compose-perfiles restore config --services 2>/dev/null) || exit $$?; \
	  grep -qx backup <<< "$$servicios" || \
	    { ui_bad "este runtime no incluye la capa de restore" "restaurar requiere el perfil restore" >&2; exit 2; }

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
