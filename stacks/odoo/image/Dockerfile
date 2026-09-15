# Imagen Odoo con fotografía interna
# Enterprise y dominios propios se copian a capas inmutables fuera de los volúmenes de Odoo.

FROM odoo:19.0-20260810

# --- Pines de los addons ---
# Contexto aparte porque son locales al deployment; el corchete los hace opcionales.

COPY requirements.txt /tmp/requirements.txt
COPY enterprise/ /opt/odoo/enterprise/
COPY custom/ /opt/odoo/custom/

USER root
RUN if [ -s /tmp/requirements.txt ]; then pip install --no-cache-dir --break-system-packages -r /tmp/requirements.txt; fi && rm -f /tmp/requirements.txt

COPY entrypoint.sh /usr/local/bin/odoo-entrypoint.sh
RUN chmod +x /usr/local/bin/odoo-entrypoint.sh
USER odoo

ENTRYPOINT ["/usr/local/bin/odoo-entrypoint.sh"]
CMD []
