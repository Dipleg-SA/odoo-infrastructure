.PHONY: help up down logs ps nuke build \
        secrets-init secrets-perms secrets-check config-init \
        host-init host-verify timers-install notify-test monitoring-role \
        cert-issue cert-renew \
        backup-run backup-integrity restore \
        addons-sync addons odoo-install odoo-update odoo-modules pydeps-check pydeps-sync \
        require-modules require-backups require-restore require-root test verify \
        nginx-up nginx-down nginx-restart nginx-logs nginx-ps nginx-verify \
        certbot-up certbot-down certbot-restart certbot-logs certbot-ps certbot-verify \
        cloudflared-up cloudflared-down cloudflared-restart cloudflared-logs cloudflared-ps cloudflared-verify \
        dnsmasq-up dnsmasq-down dnsmasq-restart dnsmasq-logs dnsmasq-ps dnsmasq-verify \
        postgres-up postgres-down postgres-restart postgres-logs postgres-ps postgres-verify \
        odoo-up odoo-down odoo-restart odoo-logs odoo-ps odoo-verify \
        backup-up backup-down backup-restart backup-logs backup-ps backup-verify \
        prometheus-up prometheus-down prometheus-restart prometheus-logs prometheus-ps prometheus-verify \
        loki-up loki-down loki-restart loki-logs loki-ps loki-verify \
        grafana-up grafana-down grafana-restart grafana-logs grafana-ps grafana-verify \
        alloy-up alloy-down alloy-restart alloy-logs alloy-ps alloy-verify
.DEFAULT_GOAL := help

# --- Ayuda ---
# Sin target, o 'make help': lista los comandos agrupados por sección. Lee las
# cabeceras '# --- Título ---' y la anotación '##' de cada target, no mantiene nada aparte.

help:
	@awk 'BEGIN {FS = ":.*##"} \
	  /^# --- .* ---$$/ {t=$$0; sub(/^# --- /,"",t); sub(/ ---$$/,"",t); printf "\n\033[1m%s\033[0m\n", t} \
	  /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-23s\033[0m %s\n", $$1, substr($$0, index($$0,"##")+2)}' $(MAKEFILE_LIST)

# --- Inicialización de un deploy nuevo ---
# En orden: secrets-init y config-init, cargar los valores a mano, secrets-perms,
# secrets-check. Los scripts ya imprimen su propio ▶/✓/✗: el target no lo duplica.

secrets-init: ## Genera los secrets iniciales (valores dummy a completar a mano)
	scripts/secrets-init.sh

# --- Permisos de secrets ---
# Un solo script con el mapa de GIDs: --apply escribe (requiere root), --check valida.

secrets-perms: ## Aplica permisos de secrets (requiere root)
	scripts/secrets-perms.sh --apply

secrets-check: ## Verifica permisos de secrets
	scripts/secrets-perms.sh --check

# --- Config real de cada stack activo ---
# Mismo mecanismo que secrets-init, pero para los .conf/.ini/.yaml gitignoreados de
# stacks/*/config/ y addons/: un cp idempotente desde el .example de cada uno.

config-init: ## Bootstrapea los config reales desde su .example
	scripts/config-init.sh

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

timers-install: ## Instala y activa las units de systemd de este stack (requiere root)
	scripts/timers.sh install

notify-test: TARGET=notify-test
notify-test: require-root ## Dispara el aviso de fallo de punta a punta (requiere root)
	@. scripts/lib/ui.sh; unidad="$$(scripts/timers.sh notify)prueba.service"; \
	  ui_start "notify-test: $$unidad"; \
	  if ! systemctl start "$$unidad"; then \
	    ui_bad "notify-test falló" "systemctl no pudo arrancar $$unidad — ¿corriste 'sudo make timers-install'? Últimas líneas del journal:"; \
	    journalctl -u "$$unidad" -n 20 --no-pager; exit 1; \
	  fi; \
	  resultado=$$(systemctl show -p Result --value "$$unidad"); \
	  if [ "$$resultado" = "success" ]; then ui_ok "notify-test listo — Result=success, ahora confirmá que el mail llegó"; \
	  else ui_bad "notify-test falló" "Result=$$resultado — últimas líneas del journal:"; \
	    journalctl -u "$$unidad" -n 20 --no-pager; exit 1; fi

# --- Certificados ---
# Emisión a mano la primera vez —nginx no arranca sin el archivo— y renovación
# por timer de systemd. DNS-01: no necesita que el borde esté arriba.

cert-issue: ## Emite el certificado inicial
	stacks/certbot/scripts/cert.sh issue

cert-renew: ## Renueva el certificado
	stacks/certbot/scripts/cert.sh renew

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
# decide cuáles corre. docs/runbooks/ nombra el target, nunca los valores esperados.

verify: ## Verifica el deploy completo — o <stack>-verify para uno solo
	scripts/verify-stacks.sh all

host-verify: ## Verifica los prerrequisitos del SO (systemd, rotación de logs, secrets)
	scripts/verify-host.sh

# --- Ciclo de vida, stack por stack ---
# Un stack es un solo compose.yaml, así que docker compose directo alcanza: no hay
# varios archivos que agregar, y por eso no hay dispatcher. Un stack que este
# entorno no lleva falla con el error de Compose, que ya nombra el servicio.
#
# nuke no está por stack: con un contenedor cada uno no queda lógica que
# justificarlo. Está el global, más abajo.

nginx-up: ## Levanta nginx
	@. scripts/lib/ui.sh; ui_run "nginx-up" docker compose up -d nginx

nginx-down: ## Baja nginx
	@. scripts/lib/ui.sh; ui_run "nginx-down" docker compose rm -sf nginx

nginx-restart: ## Reinicia nginx, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "nginx-restart" docker compose restart nginx

nginx-logs: ## Sigue los logs de nginx
	@docker compose logs -f nginx

nginx-ps: ## Lista el contenedor de nginx
	@docker compose ps nginx

nginx-verify: ## Verifica nginx
	scripts/verify-stacks.sh nginx

certbot-up: ## Levanta certbot
	@. scripts/lib/ui.sh; ui_run "certbot-up" docker compose up -d certbot

certbot-down: ## Baja certbot
	@. scripts/lib/ui.sh; ui_run "certbot-down" docker compose rm -sf certbot

certbot-restart: ## Reinicia certbot, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "certbot-restart" docker compose restart certbot

certbot-logs: ## Sigue los logs de certbot
	@docker compose logs -f certbot

certbot-ps: ## Lista el contenedor de certbot
	@docker compose ps certbot

certbot-verify: ## Verifica certbot
	scripts/verify-stacks.sh certbot

cloudflared-up: ## Levanta cloudflared
	@. scripts/lib/ui.sh; ui_run "cloudflared-up" docker compose up -d cloudflared

cloudflared-down: ## Baja cloudflared
	@. scripts/lib/ui.sh; ui_run "cloudflared-down" docker compose rm -sf cloudflared

cloudflared-restart: ## Reinicia cloudflared, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "cloudflared-restart" docker compose restart cloudflared

cloudflared-logs: ## Sigue los logs de cloudflared
	@docker compose logs -f cloudflared

cloudflared-ps: ## Lista el contenedor de cloudflared
	@docker compose ps cloudflared

cloudflared-verify: ## Verifica cloudflared
	scripts/verify-stacks.sh cloudflared

dnsmasq-up: ## Levanta dnsmasq
	@. scripts/lib/ui.sh; ui_run "dnsmasq-up" docker compose up -d dnsmasq

dnsmasq-down: ## Baja dnsmasq
	@. scripts/lib/ui.sh; ui_run "dnsmasq-down" docker compose rm -sf dnsmasq

dnsmasq-restart: ## Reinicia dnsmasq, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "dnsmasq-restart" docker compose restart dnsmasq

dnsmasq-logs: ## Sigue los logs de dnsmasq
	@docker compose logs -f dnsmasq

dnsmasq-ps: ## Lista el contenedor de dnsmasq
	@docker compose ps dnsmasq

dnsmasq-verify: ## Verifica dnsmasq
	scripts/verify-stacks.sh dnsmasq

postgres-up: ## Levanta postgres
	@. scripts/lib/ui.sh; ui_run "postgres-up" docker compose up -d postgres

postgres-down: ## Baja postgres
	@. scripts/lib/ui.sh; ui_run "postgres-down" docker compose rm -sf postgres

postgres-restart: ## Reinicia postgres, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "postgres-restart" docker compose restart postgres

postgres-logs: ## Sigue los logs de postgres
	@docker compose logs -f postgres

postgres-ps: ## Lista el contenedor de postgres
	@docker compose ps postgres

postgres-verify: ## Verifica postgres
	scripts/verify-stacks.sh postgres

odoo-up: ## Levanta odoo
	@. scripts/lib/ui.sh; ui_run "odoo-up" docker compose up -d odoo

odoo-down: ## Baja odoo
	@. scripts/lib/ui.sh; ui_run "odoo-down" docker compose rm -sf odoo

odoo-restart: ## Reinicia odoo, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "odoo-restart" docker compose restart odoo

odoo-logs: ## Sigue los logs de odoo
	@docker compose logs -f odoo

odoo-ps: ## Lista el contenedor de odoo
	@docker compose ps odoo

odoo-verify: ## Verifica odoo
	scripts/verify-stacks.sh odoo

backup-up: ## Levanta backup
	@. scripts/lib/ui.sh; ui_run "backup-up" docker compose up -d backup

backup-down: ## Baja backup
	@. scripts/lib/ui.sh; ui_run "backup-down" docker compose rm -sf backup

backup-restart: ## Reinicia backup, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "backup-restart" docker compose restart backup

backup-logs: ## Sigue los logs de backup
	@docker compose logs -f backup

backup-ps: ## Lista el contenedor de backup
	@docker compose ps backup

backup-verify: ## Verifica backup
	scripts/verify-stacks.sh backup

prometheus-up: ## Levanta prometheus
	@. scripts/lib/ui.sh; ui_run "prometheus-up" docker compose up -d prometheus

prometheus-down: ## Baja prometheus
	@. scripts/lib/ui.sh; ui_run "prometheus-down" docker compose rm -sf prometheus

prometheus-restart: ## Reinicia prometheus, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "prometheus-restart" docker compose restart prometheus

prometheus-logs: ## Sigue los logs de prometheus
	@docker compose logs -f prometheus

prometheus-ps: ## Lista el contenedor de prometheus
	@docker compose ps prometheus

prometheus-verify: ## Verifica prometheus
	scripts/verify-stacks.sh prometheus

loki-up: ## Levanta loki
	@. scripts/lib/ui.sh; ui_run "loki-up" docker compose up -d loki

loki-down: ## Baja loki
	@. scripts/lib/ui.sh; ui_run "loki-down" docker compose rm -sf loki

loki-restart: ## Reinicia loki, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "loki-restart" docker compose restart loki

loki-logs: ## Sigue los logs de loki
	@docker compose logs -f loki

loki-ps: ## Lista el contenedor de loki
	@docker compose ps loki

loki-verify: ## Verifica loki
	scripts/verify-stacks.sh loki

grafana-up: ## Levanta grafana
	@. scripts/lib/ui.sh; ui_run "grafana-up" docker compose up -d grafana

grafana-down: ## Baja grafana
	@. scripts/lib/ui.sh; ui_run "grafana-down" docker compose rm -sf grafana

grafana-restart: ## Reinicia grafana, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "grafana-restart" docker compose restart grafana

grafana-logs: ## Sigue los logs de grafana
	@docker compose logs -f grafana

grafana-ps: ## Lista el contenedor de grafana
	@docker compose ps grafana

grafana-verify: ## Verifica grafana
	scripts/verify-stacks.sh grafana

alloy-up: ## Levanta alloy
	@. scripts/lib/ui.sh; ui_run "alloy-up" docker compose up -d alloy

alloy-down: ## Baja alloy
	@. scripts/lib/ui.sh; ui_run "alloy-down" docker compose rm -sf alloy

alloy-restart: ## Reinicia alloy, sin tocar el resto del stack
	@. scripts/lib/ui.sh; ui_run "alloy-restart" docker compose restart alloy

alloy-logs: ## Sigue los logs de alloy
	@docker compose logs -f alloy

alloy-ps: ## Lista el contenedor de alloy
	@docker compose ps alloy

alloy-verify: ## Verifica alloy
	scripts/verify-stacks.sh alloy

# --- Respaldos (árbol nuevo) ---
# El diario respalda y purga; el check verifica integridad del repositorio. No hay
# 'full': en restic todo snapshot es completo y la retención GFS la hace forget.

backup-run: require-backups ## Corre el backup diario (dump + filestore en un snapshot)
	stacks/backup/scripts/backup.sh daily

backup-integrity: require-backups ## Verifica la integridad del repositorio (restic check)
	stacks/backup/scripts/backup.sh check

restore: require-restore ## Restaura filestore y base desde un snapshot — SNAPSHOT=latest
	stacks/backup/scripts/restore.sh $(or $(SNAPSHOT),latest)

# --- Ciclo de vida del stack completo ---

up: ## Levanta el stack completo
	@. scripts/lib/ui.sh; ui_run "up" docker compose up -d

down: ## Baja el stack completo
	@. scripts/lib/ui.sh; ui_run "down" docker compose down

logs: ## Sigue los logs de todos los servicios
	@. scripts/lib/ui.sh; ui_start "logs: siguiendo todo el stack (Ctrl-C para salir)"
	@docker compose logs -f

ps: ## Lista el estado de los contenedores
	@docker compose ps

# --- Nuke ---
# El más destructivo del Makefile. Confirmación: tipear la palabra 'nuke', no Y/N.
# Nunca toca secrets/ ni .env — son credenciales de terceros, no derivables de nada.

nuke: ## Borra TODO: containers/imágenes/volúmenes del stack + addons/ + state/
	@. scripts/lib/ui.sh; \
	  ui_warn "esto borra los datos de este stack" \
	    "volúmenes, imágenes propias, addons/ y state/ — secrets/ y .env NO se tocan"; \
	  ui_confirm_nuke || exit 1; \
	  ui_run "nuke" sh -c 'docker compose down -v --rmi local --remove-orphans && \
	    rm -rf addons/.repos addons/*/*/ state/textfile/*.prom state/meta/*.txt'

# --- Addons ---
# sync clona/actualiza los árboles desde addons/addons.txt; puro host, sin contenedores.

addons-sync: ## Clona/actualiza los addons desde addons/addons.txt
	scripts/addons.sh sync

addons: ## Muestra el estado de los addons
	@. scripts/lib/ui.sh; ui_run "addons" scripts/addons.sh status

# --- Imágenes propias ---
# Las que este stack construye (odoo, postgres y dnsmasq donde esté). El build de
# odoo no clona nada: el árbol de addons entra por bind-mount, no por capa de imagen.

build: ## Construye las imágenes propias de este stack
	@. scripts/lib/ui.sh; ui_run "build" docker compose build

# --- Dependencias Python de los addons ---
# check es puro host (corre en 'make test'); sync necesita Docker para resolver
# versión contra la imagen base. Ninguno de los dos rebuildea la imagen.

pydeps-check: ## Verifica que requirements.txt cubra las external_dependencies declaradas
	scripts/pydeps.sh check

pydeps-sync: ## Pinea en requirements.txt lo que declaren los addons y todavía falte
	scripts/pydeps.sh sync

# --- Instalar/actualizar módulos ---
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

# --- Respaldar vs restaurar ---
# Dos guardas y no una: respaldar es de producción, restaurar es de los dos entornos.
# La diferencia sale de la composición, no de una lista — el entrypoint de prueba le
# pone profiles: [restore] al servicio backup, así que queda fuera del default (y de
# lo que ve timers.sh) pero sigue alcanzable para restaurar.
#
require-restore:
	@. scripts/lib/ui.sh; docker compose --profile restore config --services 2>/dev/null | grep -qx backup || \
	  { ui_bad "este stack no incluye la capa de restore" "revisar COMPOSE_FILE en .env" >&2; exit 2; }

# --- Observabilidad ---
# El rol de monitoreo no sale de la imagen: lo crea el operador contra la base ya
# viva. DROP+CREATE lo hace repetible, y con eso sirve también para rotar la clave.

monitoring-role: ## Crea (o rota) el rol de solo lectura que scrapea Postgres
	stacks/alloy/scripts/monitoring-role.sh
