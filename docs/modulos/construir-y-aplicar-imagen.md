# Construir una imagen Odoo

## Cuándo se usa

Cuando cambia la base Odoo, la edición o la huella de dependencias. Un cambio exclusivo
de código de addons no usa este procedimiento.

## Objetivo

Construir una imagen trazable con Odoo y dependencias, sin copiar custom ni Enterprise,
y dejarla seleccionada en `ODOO_IMAGE` después de que el build termine correctamente.

## Flujo rápido

1. Sincronizar candidatos y compilar las huellas de dependencias.
2. Construir solo si cambió `odoo_base`, edición, entradas o lock.
3. Recrear Odoo y verificar imagen más selección montada.

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
`runtime/addons/builds/<entorno>/`. `image.json` registra `odoo_base`,
`requirements_inputs_sha256` y `requirements_lock_sha256`; no presenta commits de
addons como contenido de la imagen.

Si `ENTORNO=<entorno> scripts/addons-runtime.sh preflight` pasa después de sincronizar,
no ejecutes `make build`: `make odoo-restart` recrea el contenedor con los binds nuevos.
Si falla por base, edición o huellas, construí y volvé a ejecutar el preflight.

Para staging y producción repetí el mismo flujo con los candidatos correspondientes,
después de validar el entorno anterior. Un cambio de edición requiere el preflight ORM,
backup y validación manual; no instala, actualiza ni desinstala módulos.

## Verificación

```bash
ENTORNO=<entorno> make odoo-verify
ENTORNO=<entorno> make verify
```

La verificación debe confirmar que Compose usa el `ODOO_IMAGE` seleccionado, que
`odoo_base` y las huellas coinciden, que los dos binds pertenecen al entorno y son de
solo lectura, y que `/tmp/odoo-addons-startup.json` coincide con los candidatos.
