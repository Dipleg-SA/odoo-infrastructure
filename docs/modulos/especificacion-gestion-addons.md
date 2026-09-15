# Especificación operativa: gestión de addons inmutables

## Estado

Implementada para las fases 1 a 6. Este documento conserva la estructura objetivo y sirve como fuente del flujo operativo.

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

El checkout de Enterprise pertenece a una única línea mayor y se selecciona por tag anotado e inmutable. No recibe webhooks ni se mezcla con el catálogo de dominios.

## Contratos implementados

- Toda operación usa `ENTORNO=desarrollo|staging|produccion`; sin esa variable falla antes de Compose.
- `scripts/addons.sh` sincroniza únicamente la rama derivada del entorno y publica el SHA completo en `.candidate-commit`.
- El webhook valida firma, catálogo y rama; actualiza solo el candidato y usa el lock del entorno.
- `scripts/build-odoo-image.sh` toma el mismo lock, exporta SHAs desde clones bare, copia Enterprise y dominios a la fotografía, resuelve dependencias y registra Nueva después de obtener digest.
- `stacks/odoo/compose.yaml` consume `ODOO_IMAGE` y no monta addons del host. El entrypoint usa Enterprise, dominios propios y Community, en ese orden.
- `scripts/image-state.sh` conserva `Nueva`, `Actual`, `Anterior`, validación y procedencia. `apply` promueve; `rollback` reactiva Anterior si no hubo operaciones de módulos.
- `scripts/odoo-module-operation.sh` exige Actual y registra que el rollback solo de imagen quedó bloqueado después de una operación exitosa.
- El backup de producción guarda base, filestore, addons e imágenes Actual/Anterior en el mismo snapshot. Restore recupera esa procedencia.

## Flujo de promoción

```text
feat/* → 19.0-dev → 19.0-stag → 19.0
webhook → Candidato → build → Nueva → validación manual → Actual
```

La promoción se ejecuta por entorno y de forma serializada. Desarrollo y staging se pueden descartar y volver a sembrar. Producción crea el backup previo mediante `apply-image`.

## Enterprise

El operador crea un tag como `19.0-ee-YYYY-MM-DD` sobre el commit autorizado y lo selecciona con `ENTORNO=<entorno> scripts/addons.sh enterprise-sync <url> <tag>`. El mismo tag y commit Enterprise deben acompañar la promoción por los tres entornos.

## Estados y reversión

`images.json` registra para cada imagen tag, digest, línea Odoo, imagen base, commit de infraestructura, tag y commit Enterprise, commits de dominios y momento UTC. Sin operaciones de módulos, `rollback-image` reactiva Anterior. Después de operar módulos, se debe restaurar el backup asociado y recuperar sus metadatos.

## Fuera de alcance

La instalación, actualización, desinstalación y validación funcional de módulos siguen siendo acciones manuales. El webhook no construye imágenes, no reinicia Odoo y no accede al socket Docker, bases, filestore, secretos ni Enterprise.
