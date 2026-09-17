# Gestionar el catálogo de addons

## Cuándo se usa

Cuando se incorpora o retira un repositorio de dominio del checkout canónico.

## Objetivo

Mantener una lista blanca de repositorios propios para candidatos e imágenes.

## Flujo rápido

1. Agregar o retirar la URL del catálogo.
2. Sincronizar el repositorio en los entornos que corresponda.
3. Confirmar el árbol y construir nuevas imágenes si se retiró un repositorio.

## A mano

`runtime/addons/catalogo.txt` contiene una URL Git por línea. Enterprise queda fuera del catálogo y se administra por tag inmutable; `custom`, `oca` y `third-party` se publican como candidatos del entorno.

## Comandos

```bash
$EDITOR runtime/addons/catalogo.txt
ENTORNO=desarrollo ADDONS_REF=feat/<nombre> make repo-sync
ENTORNO=staging make repo-sync
ENTORNO=produccion make repo-sync
ENTORNO=desarrollo ADDONS_REF=feat/<nombre> make repo-status
```

Cada repositorio nuevo debe tener `19.0-stag` y `19.0`; las features se crean localmente como `feat/*` y se publican de forma controlada sobre `19.0-stag` cuando corresponde probarlas en el servidor. El webhook solo acepta repositorios del catálogo y publica candidatos de staging o producción.

Antes de retirar un repositorio, desinstalá sus módulos, limpiá datos y dependencias manualmente en todos los entornos. Después descartá y recreá desarrollo/staging, eliminá la línea del catálogo y construí nuevas imágenes.

## Verificación

`repo-status` debe mostrar los candidatos esperados. Un repositorio retirado no debe quedar en ninguna fotografía futura y sus eventos deben ignorarse. La sincronización no construye ni aplica imágenes, reinicia servicios ni modifica módulos.
