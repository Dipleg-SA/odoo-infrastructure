# Restore de staging

## Cuándo se usa

Para sembrar o volver a sembrar staging con una copia coherente de producción, incluido el simulacro semestral. Para el primer levantamiento completo, seguí [levantar-staging](../entorno/levantar-staging.md); este procedimiento cubre el restore cuando el checkout de staging ya está preparado.

## Objetivo

La base y el filestore de staging restaurados desde el mismo snapshot de producción, con los addons de la rama de staging disponibles antes de levantar Odoo.

## Flujo rápido

El restore reemplaza los datos actuales de staging. Confirmá el entorno antes de empezar.

1. **Preparar staging.** Verificar el nombre de proyecto propio, las credenciales de lectura y las
   ramas `-stag`; ver [A mano](#a-mano).
2. **Restaurar el snapshot.** Comprobar acceso al repositorio, detener Odoo y restaurar base y
   filestore; ver [Comandos](#comandos).
3. **Sincronizar y levantar.** Actualizar addons, instalar o actualizar módulos que no están en
   producción y luego iniciar Odoo; ver [Comandos](#comandos).
4. **Validar sin escribir en producción.** Comprobar el estado, los registros y un adjunto en la UI.
   No ejecutar `make backup-run`; ver [Verificación](#verificación).

## A mano

- Confirmá que el checkout usa `envs/staging.yaml` y un `COMPOSE_PROJECT_NAME` distinto al de producción. El restore reemplaza todos los datos actuales de staging.
- `stacks/backup/config/r2.env` tiene que apuntar al repositorio de producción. `secrets/restic_password` y `secrets/restic_r2_credentials` tienen que permitir leerlo; la credencial R2 de staging debe ser **solo lectura**.
- `addons/addons.txt` debe declarar los mismos repositorios que producción y `ADDONS_BRANCH` debe elegir las ramas de staging (`<versión>-stag`). Si el stack usa Enterprise, tené también el ZIP de la misma versión de Odoo.
- Odoo en staging fuerza `ODOO_DISABLE_SMTP=1`. Las credenciales de usuario que trae la base son las de producción.

## Comandos

Primero comprobá que el repositorio sea accesible y tenga snapshots. En staging este chequeo lee R2; no inicia los timers ni escribe backups.

```bash
make backup-verify
```

El restore reemplaza la base y el filestore. Si no indicás `SNAPSHOT`, usa el último snapshot:

```bash
make odoo-down
make postgres-up
make restore                         # o SNAPSHOT=<id>
```

Antes de iniciar Odoo, sincronizá los addons de la rama de staging y reconstruí si cambiaron dependencias Python:

```bash
make repo-sync
make addons-deps
make build   # si addons-deps agregó o cambió pines
```

Si staging tiene cambios de módulos que todavía no están en producción, el restore no los instala ni actualiza: aplicá `make addons-install` o `make addons-update` según corresponda, siguiendo el runbook del módulo.

```bash
make odoo-up
make verify
```

## Verificación

`make verify` debe terminar con exit `0`. Confirmá además en la UI que podés abrir un registro restaurado y descargar un adjunto. Si el restore es parte de una prueba de módulo, probá el flujo de esa feature según [gestionar-modulo](../modulos/gestionar-modulo.md).

No uses `make backup-run` en staging: su credencial R2 es de solo lectura y este entorno no respalda producción.
