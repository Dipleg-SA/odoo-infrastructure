#!/bin/sh
# --- Credenciales de Cloudflare para certbot ---
# El secret guarda el token pelado, que es lo que también consume la verificación
# contra la API. certbot exige un INI, así que se materializa acá con umask 077
# y nunca toca el disco del host. Los argumentos pasan tal cual a certbot.

set -eu
umask 077
printf 'dns_cloudflare_api_token = %s\n' "$(cat /run/secrets/cloudflare_api_token)" > /tmp/cloudflare.ini
exec certbot "$@"
