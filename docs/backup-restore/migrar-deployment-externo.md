# Migrar un deployment externo

## Cuándo se usa

Cuando una instancia Odoo existente debe pasar a este repositorio sin importar
configuración, secretos ni código privado como si fueran parte del producto.

## Objetivo

Reconstruir un runtime reproducible, elegir Community o Enterprise con la configuración
plana y conservar la procedencia de la base, el filestore y la imagen restaurada.

## Flujo rápido

1. Obtener un backup verificable de la base, el filestore y la procedencia de la instancia.
2. Preparar el runtime y restaurar primero una copia en staging.
3. Elegir la edición, construir una imagen y validar el resultado en staging.
4. Aplicar la imagen aprobada en producción con el backup asociado.

## A mano

Copiá únicamente los secretos, configuraciones privadas y datos necesarios. No copies
un `.env` externo como fuente de selección ni mezcles su checkout de addons con el
catálogo de este repositorio.

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

Community no requiere checkout Enterprise. Enterprise requiere el checkout privado
validado, el tag anotado e inmutable y la procedencia correspondiente.

## Comandos

```bash
cp runtime/staging/compose.env.example runtime/staging/compose.env
ENTORNO=staging make secrets-init config-init
ENTORNO=staging make restore SNAPSHOT=<snapshot>
ENTORNO=staging make repo-sync
ENTORNO=staging make build
ENTORNO=staging make up
ENTORNO=staging make verify
```

Completá `ODOO_EDITION` y `TAG` antes de `build`. Si el snapshot es Enterprise,
restaurá inicialmente con esa edición y conservá el checkout privado fuera del
repositorio. Para pasar a Community, retiră manualmente los módulos Enterprise sobre
una copia aislada, cambiá el par de variables, construí la imagen Community y repetí
la validación.

```bash
ENTORNO=produccion make backup-run
ENTORNO=produccion make build
ENTORNO=produccion make validate-image NOTE="staging aprobado"
ENTORNO=produccion make apply-image
```

En producción, `apply-image` ejecuta el preflight cuando cambia la edición y exige el
backup asociado. El restore reaplica la procedencia de `Actual` y `Anterior`; no
descarga módulos Enterprise ni ejecuta operaciones funcionales automáticamente.

## Verificación

```bash
ENTORNO=staging make verify
ENTORNO=produccion make verify
ENTORNO=produccion scripts/image-state.sh show
```

Confirmá que `edition`, `edition_tag`, digest, commits de addons y procedencia
Enterprise —si corresponde— coincidan con el snapshot y la imagen activa. Si la base
conserva módulos Enterprise, el destino Community queda bloqueado hasta completar la
validación y el retiro manual sobre una copia.
