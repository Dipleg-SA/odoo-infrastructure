# --- Imagen ---
# Sin stage de build para addons: llegan por bind-mount. Solo dependencias Python y el entrypoint.

FROM odoo:19.0-20260810

COPY requirements.txt /tmp/requirements.txt

USER root
RUN pip install --no-cache-dir --break-system-packages -r /tmp/requirements.txt && rm /tmp/requirements.txt

COPY entrypoint.sh /usr/local/bin/odoo-entrypoint.sh
RUN chmod +x /usr/local/bin/odoo-entrypoint.sh
USER odoo

ENTRYPOINT ["/usr/local/bin/odoo-entrypoint.sh"]
CMD []
