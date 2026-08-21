# Configurar la rotación de logs del daemon

## Cuándo se usa

Antes de levantar el primer contenedor de producción — `config/docker/daemon.json` solo rota logs de contenedores creados **después** de aplicarlo. Aplicarlo más tarde obliga a recrear los once contenedores del stack.

## Objetivo

El daemon de Docker corriendo con el driver `json-file` acotado — el que trae `config/docker/daemon.json` — para que ningún contenedor llene el disco con logs sin rotar.

## A mano

Ninguno — el archivo ya está en el repositorio, versionado; no hay valores que completar.

## Comandos

```bash
echo "# 1 → Instalar la config y reiniciar el daemon"
sudo cp config/docker/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker
```

`dockerd` no arranca si `daemon.json` tiene claves desconocidas, comentarios simulados incluidos — si el restart falla, `journalctl -u docker` tiene el motivo exacto.

**Si ya hay contenedores corriendo, no alcanza con el restart.** El driver de logging se fija por contenedor al crearlo, no al arrancarlo — hace falta recrearlos (`docker compose up -d --force-recreate`) después de este paso, nunca antes.

## Verificación

```bash
echo "# 2 → El daemon tomó la config"
docker info --format '{{.LoggingDriver}}'
```

Tiene que dar `json-file`. Para confirmar que un contenedor puntual nació con el límite aplicado:

```bash
docker inspect <contenedor> --format '{{.HostConfig.LogConfig.Config}}'
```

Si sale vacío en un contenedor que debería tenerlo, nació antes del restart — ver [contenedor-no-rota-logs](../troubleshooting/observability/contenedor-no-rota-logs.md).
