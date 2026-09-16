# Documentación

## Propósito

Esta carpeta es el destino canónico de la documentación operativa. La estructura
unificada de `docs_v2/` se migró acá y reemplaza la organización anterior.

## Estructura de los procedimientos

Los procedimientos operativos siguen este orden:

1. `Cuándo se usa`
2. `Objetivo`
3. `Flujo rápido`, cuando el procedimiento tiene un recorrido frecuente que conviene
   mostrar antes de los detalles
4. `A mano`
5. `Comandos`
6. `Verificación`

Las subsecciones específicas de un procedimiento compuesto quedan debajo de
`Comandos` o `Verificación`; no cambian el recorrido común.

## Tipos de documento

La mayoría de los archivos son procedimientos. Hay dos documentos que conservan una
estructura propia porque no describen una operación paso a paso:

- `modulos/especificacion-gestion-addons.md`: especificación operativa y contratos.
- `reporte-pr-15.md`: reporte histórico de cambios y verificaciones.

Forzarlos dentro de la plantilla de procedimientos haría menos claro su propósito.

## Selección de edición

Cada runtime elige una sola edición cambiando únicamente estas dos variables en su
`compose.env` privado:

```ini
ODOO_EDITION=community
TAG=19.0-ce-YYYY-MM-DD
```

o:

```ini
ODOO_EDITION=enterprise
TAG=19.0-ee-YYYY-MM-DD
```

No se interpretan bloques `[community]` o `[enterprise]` y no se mantiene un segundo
archivo de perfiles. Enterprise conserva su checkout privado y su procedencia; Community
no lo necesita ni lo incorpora aunque quede un checkout residual.

## Cobertura

Los procedimientos están agrupados en `entorno/`, `modulos/`, `backup-restore/`,
`operacion/` y `credenciales/`. Cada documento indica cuándo se usa, objetivo, flujo
rápido cuando corresponde, comandos y verificación. La procedencia de edición, los
backups y los restores forman parte del procedimiento, no de una configuración paralela.
