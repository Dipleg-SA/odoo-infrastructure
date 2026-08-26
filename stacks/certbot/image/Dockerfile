# --- Imagen ---
# Sin capas propias: el stack no necesita nada que la imagen oficial no traiga ya.
# El wrapper que arma el INI de Cloudflare llega por bind-mount, no por COPY —
# es config de runtime, no parte de la imagen.

FROM certbot/dns-cloudflare:v5.7.0
