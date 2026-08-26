# --- Imagen ---
# Sin stage de build para addons: llegan por bind-mount. Solo dependencias Python y el entrypoint.

FROM odoo:19.0-20260810

# --- Pines de los addons ---
# Contexto aparte porque son locales al deployment; el corchete los hace opcionales.

COPY --from=addons requirements.tx[t] /tmp/

USER root
RUN if [ -s /tmp/requirements.txt ]; then pip install --no-cache-dir --break-system-packages -r /tmp/requirements.txt; fi && rm -f /tmp/requirements.txt

COPY entrypoint.sh /usr/local/bin/odoo-entrypoint.sh
RUN chmod +x /usr/local/bin/odoo-entrypoint.sh
USER odoo

ENTRYPOINT ["/usr/local/bin/odoo-entrypoint.sh"]
CMD []
