# --- Stacks ---
# STACKS_ONESHOT (certbot) no tiene up/down/restart: se opera con cert-issue/cert-renew.

STACKS := nginx cloudflared dnsmasq postgres odoo addons-webhook backup prometheus loki grafana alloy
STACKS_ONESHOT := certbot

# --- Macro: agrupación temática para 'make help' ---
# Los grupos se declaran en este archivo y help.awk solo presenta los targets.

MACRO_BORDE := nginx cloudflared dnsmasq certbot
MACRO_DATOS := postgres backup
MACRO_APP   := odoo addons addons-webhook
MACRO_OBS   := prometheus loki grafana alloy

include .make/layouts.mk
$(foreach s,$(STACKS),$(eval $(call stack_sextet,$(s))))
$(foreach s,$(STACKS_ONESHOT),$(eval $(call stack_oneshot,$(s))))
