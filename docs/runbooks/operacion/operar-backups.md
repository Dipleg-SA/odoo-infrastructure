# Operar backups

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar el contenedor `backup` (restic) sin tocar el resto del stack. **No es donde corrés un backup** — eso es [realizar-backup](../backup-restore/realizar-backup.md). Este runbook es solo el ciclo de vida del contenedor.

Exclusiva de producción: `require-backups` en el Makefile falla si el stack no incluye esta capa — staging y development no la llevan.

## Objetivo

El contenedor `backup` en el estado pedido. Es **un solo contenedor para las dos direcciones**: respaldar y restaurar son la misma herramienta sobre el mismo repositorio.

## Comandos

```bash
make backup-up
make backup-down
make backup-restart   # docker compose restart — no recrea el contenedor
make backup-logs
make backup-ps
make backup-verify
```

**Bajarlo no pierde nada**: el estado vive en el repositorio remoto, no en el contenedor. Lo que se detiene es la posibilidad de correr `make backup-run` hasta que vuelva a subir, y el healthcheck que vigila la frescura del último snapshot.

## Verificación

```bash
make backup-verify
```

Cubre que el repositorio sea alcanzable con snapshots de este stack, que el último traiga **las dos mitades** del estado, el registro de addons, y los dos timers activos con el nombre de este checkout.

Si el contenedor sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora. **No lo recrees para forzarlo** — le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención.

---

**Destructivo — `make nuke`.** No hay nuke por stack: borra containers, imágenes y volúmenes del stack entero, y pide tipear `nuke`. **No toca el repositorio remoto en R2** — eso vive fuera de Docker, y es justamente lo que el nuke no puede destruir.
