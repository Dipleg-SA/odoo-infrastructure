#!/bin/sh
# --- Credenciales de Cloudflare para certbot ---
# El wrapper materializa el INI efímero con umask 077 y pasa los argumentos.

set -eu
umask 077
printf 'dns_cloudflare_api_token = %s\n' "$(cat /run/secrets/cloudflare_api_token)" > /tmp/cloudflare.ini
exec certbot "$@"
