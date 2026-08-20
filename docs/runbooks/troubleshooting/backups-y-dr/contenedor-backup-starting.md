# El contenedor backup dice starting y no pasa a healthy

## Síntoma

`docker compose ps` muestra `backup` como `starting` durante mucho rato después de un arranque o reinicio.

## Diagnóstico

Con `interval: 1h` el primer chequeo tarda hasta una hora tras cada reinicio, y durante el `start_period` de 5m los fallos no cuentan. **No es un fallo.**

Para ver el estado real sin esperar:

```bash
docker inspect -f '{{range .State.Health.Log}}{{.ExitCode}} {{end}}' $(docker compose ps -q backup)
```

## Fix

Ninguno — es el comportamiento esperado. **No recrees el contenedor para forzarlo**: le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención (`RESTIC_KEEP_*`).
