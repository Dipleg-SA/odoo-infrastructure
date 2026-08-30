# --- Stacks ---
# STACKS_ONESHOT (certbot) no tiene up/down/restart: se opera con cert-issue/cert-renew.

STACKS := nginx cloudflared dnsmasq postgres odoo backup prometheus loki grafana alloy
STACKS_ONESHOT := certbot

include .make/layouts.mk
$(foreach s,$(STACKS),$(eval $(call stack_sextet,$(s))))
$(foreach s,$(STACKS_ONESHOT),$(eval $(call stack_oneshot,$(s))))
