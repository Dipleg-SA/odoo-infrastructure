# Alertas DatasourceNoData en vez de la alerta real

## Síntoma

Grafana dispara `DatasourceNoData` en vez de la alerta que debería activarse.

## Diagnóstico

Una expresión que devuelve vector vacío en el estado sano.

## Fix

Las siete reglas ya están escritas para devolver siempre un valor. Si agregás una regla nueva, no uses `metrica == 0` como consulta — eso devuelve vacío cuando la métrica no existe, en vez de `0`.
