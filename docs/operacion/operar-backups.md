# Operar backups

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar el contenedor `backup` (restic) sin tocar el resto del stack. **No es donde corrés un backup** — eso es [realizar-backup](../backup-restore/realizar-backup.md). Este runbook es solo el ciclo de vida del contenedor.

El backup recurrente es exclusivo de producción. Staging incluye el servicio `backup`
solo bajo `profiles: [restore]`, para leer el repositorio con `make restore`; development
no lo incluye. Los targets `make backup-up`/`restart` nombran explícitamente el servicio
y pueden saltar el perfil inactivo de staging — **no los uses ahí**, donde solo se
necesita el `run` puntual del restore. `make backup-run` y `make backup-integrity` sí
fallan fuera de producción.

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

Cubre el servicio `healthy`, que `r2.env` no tenga el placeholder sin reemplazar, que el endpoint termine en `.r2.cloudflarestorage.com`, que el repositorio sea alcanzable con snapshots de este stack, que el último traiga **las dos mitades** del estado, el registro de addons, y los dos timers activos con el nombre de este checkout.

Si el contenedor sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora. **No lo recrees para forzarlo** — le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención.

---

**Destructivo — `make nuke`.** No hay nuke por stack: borra containers, imágenes y volúmenes del stack entero, y pide tipear `nuke`. **No toca el repositorio remoto en R2** — eso vive fuera de Docker, y es justamente lo que el nuke no puede destruir.
