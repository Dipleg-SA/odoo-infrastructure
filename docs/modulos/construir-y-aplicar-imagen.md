# Construir y aplicar una imagen Odoo

## Cuándo se usa

Cuando un candidato de un entorno está listo para convertirse en una imagen inmutable.

## Objetivo

Construir una fotografía trazable y promoverla manualmente después de validar el entorno anterior.

## A mano

Seleccioná el tag anotado de Enterprise y confirmá que el catálogo y los candidatos estén actualizados.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo ENTERPRISE_TAG=19.0-ee-YYYY-MM-DD make build
ENTORNO=desarrollo scripts/image-state.sh show
ENTORNO=desarrollo make validate-image NOTE="validación manual"
ENTORNO=desarrollo make apply-image
```

Repetí el mismo recorrido en staging y producción usando el tag Enterprise inmutable aprobado. El build toma una fotografía bajo lock, copia Enterprise y dominios a la imagen y registra Nueva solo con build y digest exitosos.

## Verificación

`ENTORNO=<entorno> scripts/image-state.sh show` debe conservar tag, digest, línea Odoo, imagen base, commit de infraestructura, tag/commit Enterprise y commits de dominios. Compose no debe montar `/mnt/extra-addons`.
