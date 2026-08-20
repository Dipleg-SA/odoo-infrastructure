# unable to verify certificate presented by ...r2.cloudflarestorage.com

## Síntoma

pgBackRest o restic fallan al conectar a R2 con un error de verificación de certificado.

## Diagnóstico

Falta el almacén de CAs raíz. La imagen oficial de Postgres no trae `ca-certificates`.

## Fix

`docker/postgres/Dockerfile` lo instala. Si aparece este error, la imagen en uso no es la propia:

```bash
docker compose build postgres && docker compose up -d postgres
```
