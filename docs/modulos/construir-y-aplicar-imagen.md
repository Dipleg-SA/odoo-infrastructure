# Construir y aplicar una imagen Odoo

## Cuándo se usa

Cuando un candidato de un entorno está listo para convertirse en una imagen inmutable.

## Objetivo

Construir una fotografía trazable y promoverla manualmente después de validar el entorno anterior.

## Flujo rápido

1. Sincronizar candidatos y dependencias.
2. Construir la fotografía y confirmar que Nueva tiene digest.
3. Validar y aplicar la imagen en el entorno correspondiente.

## A mano

La edición sale únicamente de `ODOO_EDITION` y `TAG` en el `compose.env` del entorno. Para Community no hace falta checkout Enterprise; para Enterprise seleccioná el tag anotado y confirmá que el catálogo y los candidatos estén actualizados.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo scripts/image-state.sh show
ENTORNO=desarrollo make validate-image NOTE="validación manual"
ENTORNO=desarrollo make apply-image
```

Para Enterprise, modificá esas dos variables en `runtime/desarrollo/compose.env` y repetí el build con el checkout privado disponible. Repetí el recorrido en staging y producción con el tag inmutable aprobado. El build toma una fotografía bajo lock, incorpora solo la edición seleccionada y registra Nueva después de confirmar build y digest exitosos. La instalación o actualización funcional de módulos Enterprise queda para una operación manual posterior.

## Verificación

`ENTORNO=<entorno> scripts/image-state.sh show` debe conservar tag, digest, línea Odoo, imagen base, commit de infraestructura, tag/commit Enterprise y commits de dominios. Compose no debe montar `/mnt/extra-addons`.
