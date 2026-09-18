# Especificación operativa: gestión de addons inmutables

## Estado

Implementada. Este documento describe el contrato vigente para candidatos, builds y
operación manual de módulos.

## Objetivo

Compartir catálogo y clones bare, pero mantener por entorno los árboles ejecutables,
secretos, configuración, estado, volúmenes e identidad Compose. El webhook solo publica
código candidato; Odoo combina la imagen indicada por `ODOO_IMAGE` con sus binds.

## Estructura objetivo

```text
runtime/<entorno>/
├── compose.yaml
├── compose.env.example
├── compose.env                 # privado
├── config/                     # privado
├── secrets/                    # privado
├── addons/
│   ├── custom/<dominio>/       # candidatos propios del entorno
│   ├── enterprise/             # checkout privado del entorno
│   └── requirements.*          # lock y huellas derivados
└── state/meta/                 # metadata asociada a backups
runtime/addons/
├── catalogo.txt                # privado, solo dominios
├── .repos/<dominio>.git/       # clones bare compartidos
└── builds/<entorno>/<id>/      # fotografía y procedencia del build
```

## Contratos implementados

- Toda operación usa `ENTORNO=desarrollo|staging|produccion`; sin esa variable falla antes de Compose.
- Cada `compose.env` declara `ADDONS_REF`: desarrollo usa `feat/*`, staging consume `19.0-stag` y producción `19.0`.
- El webhook valida firma, catálogo y rama; actualiza solo el candidato y usa el lock del entorno.
- `addons-runtime-init` crea los tres destinos custom antes de Compose con grupo `65532` y modo `2775` en Linux.
- `scripts/build-odoo-image.sh` toma el mismo lock, fotografía declaraciones de dependencias y construye Odoo sin copiar addons.
- El build actualiza `ODOO_IMAGE` únicamente después de obtener el digest y registra `odoo_base` y ambas huellas bajo `runtime/addons/builds/<entorno>/`.
- `stacks/odoo/compose.yaml` monta custom y Enterprise del entorno como solo lectura; el entrypoint registra los commits cargados antes de iniciar.
- `scripts/odoo-module-operation.sh` ejecuta operaciones ORM manuales bajo el mismo lock y recrea Odoo al terminar.
- El backup guarda base, filestore y `/tmp/odoo-addons-startup.json`; no presenta candidatos posteriores como código ejecutado.

## Flujo de promoción

```text
feat/* local → 19.0-stag → PR aprobado → 19.0
webhook → candidato → recreación manual → selección cargada → promotion-verify
```

La promoción de código se serializa por entorno. Staging puede contener varias features;
su validación y el PR incluyen todo el delta con producción. Si se descartan cambios,
staging se realinea explícitamente con `19.0`, conservando un respaldo Git. Producción
ejecuta el backup requerido antes de la recreación u operación funcional final. Un build
solo entra si cambian base, edición o dependencias.

## Edición y procedencia

`ODOO_EDITION` y `TAG` seleccionan la variante antes de construir. La metadata del build
registra edición, tag, digest, línea Odoo, `odoo_base`, commit de infraestructura,
huellas de dependencias y momento UTC. Los commits de dominios pertenecen a la selección
de arranque, no al contenido de la imagen.

Una transición entre ediciones no convierte módulos ni registros. El preflight ORM y la
validación manual deben terminar antes de construir producción. La recuperación siempre
combina restore de datos con un build explícito de la edición declarada.

## Enterprise y Community

Enterprise se selecciona con un tag anotado e inmutable mediante
`scripts/addons.sh enterprise-sync`; Community usa `TAG=19.0-ce-YYYY-MM-DD` y no exige
checkout Enterprise. Cada entorno mantiene su propio checkout y puede conservar un
commit distinto durante la validación, siempre mediante un tag anotado e inmutable.

## Recuperación

No hay estados `Nueva`, `Actual` o `Anterior`, ni comandos de promoción o rollback de
imágenes. Ante una falla, detené el runtime si corresponde, restaurá base y filestore,
corregí la configuración o los candidatos, reconstruí solo si cambió el runtime y
verificá imagen, mounts y selección cargada.

## Fuera de alcance

La instalación, actualización, desinstalación y validación funcional de módulos siguen
siendo acciones manuales. El webhook no construye imágenes, no reinicia Odoo y no accede
al socket Docker, bases, filestore, secretos ni Enterprise.
