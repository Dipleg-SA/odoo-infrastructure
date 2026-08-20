# El exporter de Postgres no conecta

## Síntoma

El exporter de métricas de Postgres no logra autenticarse contra la base.

## Diagnóstico

La password del rol `monitoring` y la del archivo `secrets/postgres_exporter_password` se desincronizaron.

## Fix

Rotar el secret **no** cambia la base: hace falta además

```sql
ALTER ROLE monitoring PASSWORD '<valor-nuevo>';
```

Ver [levantar-produccion](../../entorno/levantar-produccion.md) fase 8 para cómo se crea ese rol la primera vez.
