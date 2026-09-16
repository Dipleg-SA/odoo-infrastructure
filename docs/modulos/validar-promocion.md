# Validar una promoción

## Cuándo se usa

Antes de aplicar una imagen Nueva a un entorno o de continuarla hacia el siguiente.

## Objetivo

Dejar evidencia manual y conservar una reversión consistente.

## Flujo rápido

1. Validar la imagen en desarrollo.
2. Restaurar y validar en staging.
3. Aplicar en producción solo con la evidencia anterior aprobada.

## A mano

Validá la imagen en desarrollo, luego staging con datos restaurados de producción y finalmente producción. Si cambia `ODOO_EDITION`, ejecutá el preflight de solo lectura en cada entorno y no ejecutes operaciones funcionales desde el webhook.

## Comandos

```bash
ENTORNO=desarrollo make validate-image NOTE="flujo funcional aprobado"
ENTORNO=desarrollo make apply-image
ENTORNO=staging make restore SNAPSHOT=latest
ENTORNO=staging make validate-image NOTE="regresión aprobada"
ENTORNO=staging make apply-image
ENTORNO=produccion make validate-image NOTE="staging aprobado"
ENTORNO=produccion make apply-image
```

`apply-image` mueve Nueva a Actual y conserva la Actual previa en Anterior. Si una validación falla sin operaciones de módulos, ejecutá `rollback-image`. Si hubo operaciones de módulos, restaurá el backup asociado antes de recuperar la imagen.

Para Community→Enterprise, cambiá `ODOO_EDITION` y `TAG` en el `compose.env`, construí una Nueva Enterprise y validala progresivamente. En producción `apply-image` exige el backup asociado y conserva la imagen Community en Anterior; esa frontera no habilita un rollback ordinario hacia otra edición. Instalá o actualizá módulos Enterprise después de aplicar la imagen, de forma manual y con el backup preservado.

## Verificación

```bash
ENTORNO=<entorno> scripts/image-state.sh show
ENTORNO=<entorno> make verify
```

La procedencia y la nota de validación deben corresponder a la imagen ejecutada.
