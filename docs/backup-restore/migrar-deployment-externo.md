# Migrar un deployment externo

## Cuándo se usa

Cuando una instancia Odoo existente debe pasar a este repositorio sin importar
configuración, secretos ni código privado como si fueran parte del producto.

## Objetivo

Reconstruir un runtime reproducible, elegir Community o Enterprise con la configuración
plana y conservar la procedencia de la base, el filestore, la imagen y el código
ejecutado.

## Flujo rápido

1. Obtener un backup verificable de base, filestore y procedencia de la instancia.
2. Preparar el runtime y restaurar primero una copia en staging.
3. Elegir la edición, reconstruir los mounts, construir y validar staging.
4. Reconstruir los mounts y levantar producción con el backup asociado.

## A mano

Copiá únicamente secretos, configuraciones privadas, datos y evidencia verificable de
los commits ejecutados. No copies un `.env` externo como fuente de selección ni mezcles
su checkout de addons con los árboles de este runtime.

La elección usa solo estas variables en `runtime/<entorno>/compose.env`:

```ini
ODOO_EDITION=community
TAG=19.0-ce-YYYY-MM-DD
```

o:

```ini
ODOO_EDITION=enterprise
TAG=19.0-ee-YYYY-MM-DD
```

Community no requiere checkout Enterprise. Enterprise requiere checkout privado validado,
tag anotado e inmutable y procedencia correspondiente.

## Comandos

```bash
cp runtime/staging/compose.env.example runtime/staging/compose.env
ENTORNO=staging make secrets-init config-init
ENTORNO=staging make addons-runtime-init
ENTORNO=staging make restore SNAPSHOT=<snapshot>
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
ENTORNO=staging make up
ENTORNO=staging make verify
```

Completá `ODOO_EDITION` y `TAG` antes de `build`. Si el snapshot es Enterprise,
restaurá inicialmente con esa edición y conservá el checkout privado fuera del
repositorio. Para pasar a Community, retirá manualmente los módulos Enterprise sobre
una copia aislada, cambiá el par de variables, construí y repetí la validación.

```bash
ENTORNO=produccion make backup-run
ENTORNO=produccion make addons-runtime-init
ENTORNO=produccion make repo-sync
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
ENTORNO=produccion make up
ENTORNO=produccion make verify
```

## Verificación

Confirmá que edición, tag, digest y huellas de la imagen coincidan, y que los commits de
`/tmp/odoo-addons-startup.json` correspondan a la procedencia importada. Enterprise se
reconstruye por entorno bajo su propio `addons/enterprise`. Si la base conserva
módulos Enterprise, el destino Community queda bloqueado hasta completar la validación
y el retiro manual sobre una copia.
