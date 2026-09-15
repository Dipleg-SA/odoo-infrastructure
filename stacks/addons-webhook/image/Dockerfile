# Imagen base del receptor
# La etiqueta fija Python y Debian sin depender de paquetes externos.
FROM python:3.13.15-slim-bookworm

# Cliente de repositorios
# Git y OpenSSH permiten leer las URL HTTPS y SSH del catálogo.
RUN apt-get update \
    && apt-get install --no-install-recommends -y git openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Ejecución Python reproducible
# Evita bytecode en la imagen y entrega los logs sin buffer.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY app/server.py ./server.py
EXPOSE 8080
CMD ["python", "/app/server.py"]
