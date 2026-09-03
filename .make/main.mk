# --- Stacks ---
# STACKS_ONESHOT (certbot) no tiene up/down/restart: se opera con cert-issue/cert-renew.

STACKS := nginx cloudflared dnsmasq postgres odoo backup prometheus loki grafana alloy
STACKS_ONESHOT := certbot

# --- Macro: agrupación temática para 'make help' ---
# No cambia qué stacks existen ni cómo se orquestan — solo cómo help.awk los presenta.
# Los nombres y el agrupamiento salen de los propios '##' de ARCHITECTURE.md.

MACRO_BORDE := nginx cloudflared dnsmasq certbot
MACRO_DATOS := postgres backup
MACRO_APP   := odoo repo addons
MACRO_OBS   := prometheus loki grafana alloy

include .make/layouts.mk
$(foreach s,$(STACKS),$(eval $(call stack_sextet,$(s))))
$(foreach s,$(STACKS_ONESHOT),$(eval $(call stack_oneshot,$(s))))
