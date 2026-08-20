# Un contenedor no rota sus logs (LogConfig vacío)

## Síntoma

Un contenedor específico no tiene rotación de logs aplicada, mientras otros sí.

## Diagnóstico

```bash
docker inspect -f '{{.HostConfig.LogConfig}}' <contenedor>
```

Es anterior al restart del daemon. La rotación de `config/docker/daemon.json` solo aplica a contenedores **creados después** de reiniciar el daemon.

## Fix

```bash
docker compose up -d --force-recreate <servicio>
```
