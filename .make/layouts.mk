# --- Sexteto por stack ---
# up/down/restart/logs/ps/verify para un stack de un solo contenedor, sintetizado en help.awk.

define stack_sextet
$(1)-up:
	@. scripts/lib/ui.sh; ui_run "$(1)-up" docker compose up -d $(1)

$(1)-down:
	@. scripts/lib/ui.sh; ui_run "$(1)-down" docker compose rm -sf $(1)

$(1)-restart:
	@. scripts/lib/ui.sh; ui_run "$(1)-restart" docker compose restart $(1)

$(1)-logs:
	@. scripts/ui/components.sh; ui_section "$(1)-logs: siguiendo (Ctrl-C para salir)"; docker compose logs -f $(1)

$(1)-ps:
	@. scripts/ui/components.sh; salida=$$$$(docker compose ps $(1)) || exit $$$$?; printf '%s\n' "$$$$salida" | ui_color_status | ui_table_frame

$(1)-verify:
	scripts/verify-stacks.sh $(1)

endef

# --- Trío por stack de un solo uso ---
# logs/ps/verify para un stack sin up/down/restart propio: lo opera su propio comando.

define stack_oneshot
$(1)-logs:
	@. scripts/ui/components.sh; ui_section "$(1)-logs: siguiendo (Ctrl-C para salir)"; docker compose logs -f $(1)

$(1)-ps:
	@. scripts/ui/components.sh; salida=$$$$(docker compose ps $(1)) || exit $$$$?; printf '%s\n' "$$$$salida" | ui_color_status | ui_table_frame

$(1)-verify:
	scripts/verify-stacks.sh $(1)

endef
