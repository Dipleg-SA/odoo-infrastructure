# --- Stacks con sexteto completo ---
# certbot queda afuera: no es un servicio de larga vida, se opera con
# cert-issue/cert-renew (ver el bloque de Certificados en el Makefile).

STACKS := nginx cloudflared dnsmasq postgres odoo backup prometheus loki grafana alloy

include .make/layouts.mk
$(foreach s,$(STACKS),$(eval $(call stack_sextet,$(s))))
