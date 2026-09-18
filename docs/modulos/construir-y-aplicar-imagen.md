# Construir una imagen Odoo

## Cuándo se usa

Cuando los candidatos y la configuración de un entorno están listos para generar una
imagen inmutable.

## Objetivo

Construir una fotografía trazable y dejarla seleccionada en `ODOO_IMAGE` después de que
el build termine correctamente.

## Flujo rápido

1. Sincronizar candidatos y dependencias.
2. Construir la imagen Odoo y las auxiliares.
3. Levantar Odoo y verificar la referencia seleccionada.

## A mano

La edición sale únicamente de `ODOO_EDITION` y `TAG` en el `compose.env` del entorno.
Community no necesita checkout Enterprise; Enterprise exige un checkout privado limpio,
un tag anotado e inmutable y sus dependencias disponibles.

## Comandos

```bash
ENTORNO=desarrollo make repo-sync
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make odoo-up
ENTORNO=desarrollo make odoo-verify
```

`make build` construye Odoo y las imágenes auxiliares. Solo después de obtener el digest
actualiza `ODOO_IMAGE` en `runtime/<entorno>/compose.env` y guarda la procedencia bajo
`runtime/addons/builds/<entorno>/`. No hay promoción, rollback ni imagen alternativa.

Para staging y producción repetí el mismo flujo con los candidatos correspondientes,
después de validar el entorno anterior. Un cambio de edición requiere el preflight ORM,
backup y validación manual; no instala, actualiza ni desinstala módulos.

## Verificación

```bash
ENTORNO=<entorno> make odoo-verify
ENTORNO=<entorno> make verify
```

La verificación debe confirmar que Compose usa el `ODOO_IMAGE` seleccionado, que la
imagen existe localmente, que su procedencia coincide con edición y tag, y que no monta
`/mnt/extra-addons`.
