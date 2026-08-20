# no configuration file provided: not found

## Síntoma

Todo comando de Compose falla en un deploy que ya funcionaba, típicamente después de actualizar el repositorio:

```
no configuration file provided: not found
```

## Diagnóstico

Los archivos de Compose viven bajo `docker/` y no hay ninguno en la raíz, así que Compose no auto-descubre nada: el stack sale de `COMPOSE_FILE`. Y `.env` no se versiona, así que ningún `git pull` lo actualiza.

```bash
grep COMPOSE_FILE .env
```

Un valor sin el prefijo `docker/` —`compose.yaml`, `compose.staging.yaml`, `compose.dev.yaml`— es un `.env` anterior a la mudanza. `make host-verify` lo marca como `la composición resuelve`.

## Fix

Prefijar el valor con `docker/` en `.env`, y comparar contra la plantilla del entorno por si quedó algo más atrás:

```bash
diff <(sort .env) <(sort .env.prod.example) | grep COMPOSE
```

No hay nada que recrear: el nombre del stack no cambia, así que volúmenes, imágenes y contenedores siguen siendo los mismos.
