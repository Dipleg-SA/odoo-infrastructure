# Ruido en los logs de cloudflared

## Síntoma

Pedidos a `/actuator/env`, `/info.php`, `/config.json`, `/.env`, rutas de Jira/WordPress, en los logs de `cloudflared`.

## Diagnóstico

Son bots escaneando el hostname público, aparecen desde que el DNS queda expuesto.

## Fix

No es un compromiso; no hace falta actuar. Al contar errores conviene acotar la ventana (`--since 5m`) para no mezclarlos con fallas viejas ya resueltas.
