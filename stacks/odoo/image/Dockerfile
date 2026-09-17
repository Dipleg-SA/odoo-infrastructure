# Dependencias Python compiladas
# Las herramientas nativas viven solo en esta etapa y no llegan a la imagen final.

FROM odoo:19.0-20260810 AS python-deps

COPY requirements.lock.txt /tmp/requirements.txt
COPY requirements.sources/ /tmp/requirements.sources/

USER root
RUN mkdir -p /tmp/wheels && if [ -s /tmp/requirements.txt ]; then apt-get update && apt-get install -y --no-install-recommends build-essential python3-dev swig libssl-dev && pip wheel --wheel-dir /tmp/wheels -r /tmp/requirements.txt && rm -rf /var/lib/apt/lists/*; fi

# Imagen Odoo con fotografía interna
# Enterprise y dominios propios se copian a capas inmutables; Enterprise queda vacío en Community.

FROM odoo:19.0-20260810

COPY --from=python-deps /tmp/wheels/ /tmp/wheels/
COPY enterprise/ /opt/odoo/enterprise/
COPY custom/ /opt/odoo/custom/

USER root
RUN if find /tmp/wheels -maxdepth 1 -name '*.whl' -print -quit | grep -q .; then pip install --no-cache-dir --break-system-packages --ignore-installed --no-index --find-links=/tmp/wheels /tmp/wheels/*.whl; fi && rm -rf /tmp/wheels

COPY entrypoint.sh /usr/local/bin/odoo-entrypoint.sh
RUN chmod +x /usr/local/bin/odoo-entrypoint.sh
USER odoo

ENTRYPOINT ["/usr/local/bin/odoo-entrypoint.sh"]
CMD []
