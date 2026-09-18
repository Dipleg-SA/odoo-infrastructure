# Gestionar el catálogo de addons

## Cuándo se usa

Cuando se incorpora o retira un repositorio de dominio del checkout canónico.

## Objetivo

Mantener una lista blanca de repositorios propios para candidatos montados.

## Flujo rápido

1. Agregar o retirar la URL del catálogo.
2. Sincronizar el repositorio en los entornos que corresponda.
3. Confirmar cada árbol, desinstalar antes de retirar código y recrear Odoo.

## A mano

`runtime/addons/catalogo.txt` contiene una URL Git por línea. Enterprise queda fuera del
catálogo y se administra por tag inmutable. Cada URL se publica bajo
`runtime/<entorno>/addons/custom/<dominio>`; no hay categorías ejecutables compartidas.

## Comandos

```bash
$EDITOR runtime/addons/catalogo.txt
make addons-runtime-init
ENTORNO=desarrollo make repo-sync
ENTORNO=staging make repo-sync
ENTORNO=produccion make repo-sync
ENTORNO=desarrollo make repo-status
```

Cada repositorio nuevo debe tener `19.0-stag` y `19.0`. Desarrollo usa la `feat/*` declarada en su runtime y la inicializa desde `19.0` cuando falta; staging y producción solo consumen sus referencias declaradas. El webhook solo acepta repositorios del catálogo y publica candidatos de staging o producción.

Antes de retirar un repositorio, desinstalá sus módulos y limpiá datos manualmente en
todos los entornos. Después eliminá la línea, sincronizá y recreá cada Odoo. Construí una
imagen nueva únicamente si también cambió la huella de dependencias.

## Verificación

`repo-status` debe mostrar los candidatos esperados por entorno. Un repositorio retirado
no debe quedar montado después de la recreación y sus eventos deben ignorarse. La
sincronización no construye imágenes, recrea servicios ni modifica módulos.
