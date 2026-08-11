# syntax=docker/dockerfile:1

# --- Base: Postgres oficial, tag pineado ---

FROM postgres:17.10

# --- pgBackRest ---
# Versión pineada por PGDG; ca-certificates sin pinear a propósito (rompe TLS con R2 si se congela).

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        pgbackrest=2.59.0-1.pgdg13+1 \
    && rm -rf /var/lib/apt/lists/*

# --- Directorios de pgBackRest ---
# conf.d es el include path por defecto: ahí se monta el secret con las claves de R2.

RUN mkdir -p /etc/pgbackrest/conf.d /var/log/pgbackrest /var/spool/pgbackrest \
    && chown -R postgres:postgres /etc/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
