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

Lo crea `make monitoring-role`, que es repetible: ver [levantar-produccion](../../entorno/levantar-produccion.md), bloque 8 · Monitoring.
