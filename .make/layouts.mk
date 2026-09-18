# --- Sexteto por stack ---
# up/down/restart/logs/ps/verify para un stack de un solo contenedor, sintetizado en help.awk.

define stack_sextet
$(1)-up:
	@if [ "$(1)" = "odoo" ]; then scripts/odoo-lifecycle.sh up; \
	else . scripts/lib/ui.sh; ui_run "$(1)-up" $(CONTEXTO_COMPOSE) up -d $(1); fi
	@if [ "$(1)" = "odoo" ]; then $(MAKE) odoo-report-config; fi

$(1)-down:
	@. scripts/lib/ui.sh; ui_run "$(1)-down" $(CONTEXTO_COMPOSE) rm -sf $(1)

$(1)-restart:
	@if [ "$(1)" = "odoo" ]; then scripts/odoo-lifecycle.sh restart; \
	else . scripts/lib/ui.sh; ui_run "$(1)-restart" $(CONTEXTO_COMPOSE) restart $(1); fi

$(1)-logs:
	@. scripts/ui/components.sh; ui_section "$(1)-logs: siguiendo (Ctrl-C para salir)"; $(CONTEXTO_COMPOSE) logs -f $(1)

$(1)-ps:
	@. scripts/ui/components.sh; salida=$$$$($(CONTEXTO_COMPOSE) ps --format "{{.Name}}$$$$(printf '\t'){{.Status}}$$$$(printf '\t'){{.Ports}}" $(1)) || exit $$$$?; printf '%s\n' "$$$$salida" | ui_ps_table

$(1)-verify:
	scripts/verify-stacks.sh $(1)

endef

# --- Trío por stack de un solo uso ---
# logs/ps/verify para un stack sin up/down/restart propio: lo opera su propio comando.

define stack_oneshot
$(1)-logs:
	@. scripts/ui/components.sh; ui_section "$(1)-logs: siguiendo (Ctrl-C para salir)"; $(CONTEXTO_COMPOSE) logs -f $(1)

$(1)-ps:
	@. scripts/ui/components.sh; salida=$$$$($(CONTEXTO_COMPOSE) ps --format "{{.Name}}$$$$(printf '\t'){{.Status}}$$$$(printf '\t'){{.Ports}}" $(1)) || exit $$$$?; printf '%s\n' "$$$$salida" | ui_ps_table

$(1)-verify:
	scripts/verify-stacks.sh $(1)

endef
