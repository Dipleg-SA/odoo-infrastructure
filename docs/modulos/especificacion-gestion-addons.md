# Especificación operativa: gestión de addons inmutables

## Estado

Implementada. Este documento conserva la estructura vigente y sirve como fuente del flujo operativo.

## Objetivo

Compartir un checkout por línea mayor de Odoo entre desarrollo, staging y producción, manteniendo separados secretos, configuración, estado, volúmenes e identidad Compose. El webhook solo recibe código candidato; Odoo ejecuta imágenes inmutables seleccionadas manualmente.

## Estructura objetivo

```text
runtime/<entorno>/
├── compose.yaml
├── compose.env.example
├── compose.env                 # privado
├── config/                     # privado
├── secrets/                    # privado
└── state/
    ├── images.json             # Nueva, Actual, Anterior y validación
    └── meta/                   # procedencia asociada a backups
runtime/addons/
├── catalogo.txt                # privado, solo dominios
├── .repos/<dominio>.git/       # clones bare compartidos
├── enterprise/                 # checkout privado, fuera del catálogo
├── custom/<entorno>/<dominio>/ # candidatos publicados por webhook
└── builds/<entorno>/<id>/      # fotografía del build
```

El checkout de Enterprise pertenece a una única línea mayor y se selecciona por tag anotado e inmutable. No recibe webhooks ni se mezcla con el catálogo de dominios. Las operaciones puntuales del receptor se exponen también como targets `addons-webhook-*` de Make, igual que los demás stacks.

## Contratos implementados

- Toda operación usa `ENTORNO=desarrollo|staging|produccion`; sin esa variable falla antes de Compose.
- `scripts/addons.sh` sincroniza `ADDONS_REF=feat/*` solo en desarrollo, `19.0-stag` en staging y `19.0` en producción; publica el SHA completo en `.candidate-commit`.
- El webhook valida firma, catálogo y rama; actualiza solo el candidato y usa el lock del entorno.
- `scripts/build-odoo-image.sh` toma el mismo lock, exporta SHAs desde clones bare, copia solo la edición seleccionada y los dominios a la fotografía, resuelve dependencias y registra Nueva después de obtener digest.
- `stacks/odoo/compose.yaml` consume `ODOO_IMAGE` y no monta addons del host. El entrypoint usa Enterprise, dominios propios y Community, en ese orden.
- `scripts/image-state.sh` conserva `Nueva`, `Actual`, `Anterior`, validación y procedencia. `apply` promueve; `rollback` reactiva Anterior si no hubo operaciones de módulos.
- `scripts/odoo-module-operation.sh` exige Actual y registra que el rollback solo de imagen quedó bloqueado después de una operación exitosa.
- El backup de producción guarda base, filestore, addons e imágenes Actual/Anterior en el mismo snapshot, incluyendo edición, tag y procedencia. Restore recupera esa información sin descargar código Enterprise por su cuenta.

## Flujo de promoción

```text
feat/* local → 19.0-stag → PR aprobado → 19.0
webhook → Candidato → build/apply manual → Actual validada → promotion-verify
```

La promoción se ejecuta por entorno y de forma serializada. Staging puede contener varias features; su validación y el PR incluyen todo el delta con producción. Si se descartan cambios, staging se realinea explícitamente con `19.0`, conservando un respaldo Git; no es un rebase. Producción crea el backup previo mediante `apply-image`. Si `ODOO_EDITION` cambia, el preflight consulta la base y la promoción conserva la edición anterior como frontera de recuperación.

## Edición en candidatos y fotografías

`ODOO_EDITION` y `TAG` seleccionan la variante antes de sincronizar, construir o promover. El candidato de dominio sigue la rama del entorno; la fotografía agrega `edition`, `edition_tag`, digest, commits y momento de build. Enterprise agrega su tag, commit e inventario de módulos; Community registra esos campos vacíos y no incorpora el checkout privado.

Una transición entre ediciones no convierte módulos ni registros. El backup asociado conserva la base, el filestore y la fotografía activa para poder restaurar el estado anterior antes de cualquier operación funcional.

## Enterprise y Community

El operador crea un tag como `19.0-ee-YYYY-MM-DD` sobre el commit autorizado y lo selecciona con `ENTORNO=<entorno> scripts/addons.sh enterprise-sync <url> <tag>`. El mismo tag y commit Enterprise deben acompañar la promoción por los tres entornos.

Community usa `TAG=19.0-ce-YYYY-MM-DD`, no exige checkout Enterprise y puede avanzar con los mismos candidatos de dominios. El retiro de Enterprise exige validar que la base no conserve módulos Enterprise instalados.

## Estados y reversión

`images.json` registra para cada imagen edición, tag de edición, referencia interna, digest, línea Odoo, imagen base, commit de infraestructura, tag y commit Enterprise cuando corresponda, commits de dominios y momento UTC. El restore reaplica `Actual` y `Anterior` desde esa procedencia. Sin operaciones de módulos, `rollback-image` reactiva Anterior; después de operar módulos, se debe restaurar el backup asociado y recuperar sus metadatos.

## Fuera de alcance

La instalación, actualización, desinstalación y validación funcional de módulos siguen siendo acciones manuales. El webhook no construye imágenes, no reinicia Odoo y no accede al socket Docker, bases, filestore, secretos ni Enterprise.
