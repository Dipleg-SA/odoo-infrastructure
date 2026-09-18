# Especificación operativa: gestión de addons inmutables

## Estado

Implementada. Este documento describe el contrato vigente para candidatos, builds y
operación manual de módulos.

## Objetivo

Compartir un checkout por línea mayor de Odoo entre desarrollo, staging y producción,
manteniendo separados secretos, configuración, estado, volúmenes e identidad Compose.
El webhook solo recibe código candidato; Odoo ejecuta la única imagen indicada por
`ODOO_IMAGE`.

## Estructura objetivo

```text
runtime/<entorno>/
├── compose.yaml
├── compose.env.example
├── compose.env                 # privado
├── config/                     # privado
├── secrets/                    # privado
└── state/
    └── meta/                   # metadata asociada a backups
runtime/addons/
├── catalogo.txt                # privado, solo dominios
├── .repos/<dominio>.git/       # clones bare compartidos
├── enterprise/                 # checkout privado, fuera del catálogo
├── custom/<entorno>/<dominio>/ # candidatos publicados por webhook
└── builds/<entorno>/<id>/      # fotografía y procedencia del build
```

## Contratos implementados

- Toda operación usa `ENTORNO=desarrollo|staging|produccion`; sin esa variable falla antes de Compose.
- Cada `compose.env` declara `ADDONS_REF`: desarrollo usa `feat/*`, staging consume `19.0-stag` y producción `19.0`.
- El webhook valida firma, catálogo y rama; actualiza solo el candidato y usa el lock del entorno.
- `scripts/build-odoo-image.sh` toma el mismo lock, exporta SHAs desde clones bare, copia la edición seleccionada y los dominios, compila dependencias y fija referencias Git.
- El build actualiza `ODOO_IMAGE` únicamente después de obtener el digest y guarda `image.json` bajo `runtime/addons/builds/<entorno>/`.
- `stacks/odoo/compose.yaml` consume `ODOO_IMAGE` y no monta addons del host. El entrypoint usa Enterprise, dominios propios y Community, en ese orden.
- `scripts/odoo-module-operation.sh` ejecuta las operaciones ORM manuales contra la imagen seleccionada.
- El backup de producción guarda base, filestore, addons y metadata suficiente para reconstruir la imagen; no conserva una selección de imágenes alternativa.

## Flujo de promoción

```text
feat/* local → 19.0-stag → PR aprobado → 19.0
webhook → candidato → build manual → ODOO_IMAGE seleccionado → promotion-verify
```

La promoción de código se serializa por entorno. Staging puede contener varias features;
su validación y el PR incluyen todo el delta con producción. Si se descartan cambios,
staging se realinea explícitamente con `19.0`, conservando un respaldo Git. Producción
ejecuta el backup requerido antes del build y la validación final.

## Edición y procedencia

`ODOO_EDITION` y `TAG` seleccionan la variante antes de construir. La metadata del build
registra edición, tag, digest, línea Odoo, imagen base, commit de infraestructura,
commits de dominios y momento UTC. Enterprise agrega su tag, commit e inventario de
módulos; Community no incorpora el checkout privado.

Una transición entre ediciones no convierte módulos ni registros. El preflight ORM y la
validación manual deben terminar antes de construir producción. La recuperación siempre
combina restore de datos con un build explícito de la edición declarada.

## Enterprise y Community

Enterprise se selecciona con un tag anotado e inmutable mediante
`scripts/addons.sh enterprise-sync`; Community usa `TAG=19.0-ce-YYYY-MM-DD` y no exige
checkout Enterprise. El mismo tag y commit Enterprise deben acompañar los tres entornos.

## Recuperación

No hay estados `Nueva`, `Actual` o `Anterior`, ni comandos de promoción o rollback de
imágenes. Ante una falla, detené el runtime si corresponde, restaurá base y filestore,
corregí la configuración o los candidatos, construí de nuevo y verificá `ODOO_IMAGE`.

## Fuera de alcance

La instalación, actualización, desinstalación y validación funcional de módulos siguen
siendo acciones manuales. El webhook no construye imágenes, no reinicia Odoo y no accede
al socket Docker, bases, filestore, secretos ni Enterprise.
