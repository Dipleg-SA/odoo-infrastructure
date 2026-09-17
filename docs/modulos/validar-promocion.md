# Validar una promoción

## Cuándo se usa

Antes de aplicar una imagen Nueva a un entorno o de continuarla hacia el siguiente.

## Objetivo

Dejar evidencia manual y conservar una reversión consistente.

## Flujo rápido

1. Probar la feature localmente.
2. Restaurar y validar en staging el conjunto completo de `19.0-stag`.
3. Promover ese conjunto por PR y verificar la equivalencia antes del build productivo.

## A mano

Validá la feature localmente, luego staging con datos restaurados de producción. La evidencia se registra con `validate-image` sobre la imagen `Actual` de staging e identifica el conjunto de `19.0-stag` probado. No promociones si esa imagen no tiene `validation.result: ok`, si la nota no identifica la prueba o si staging cambió después de validar. Si cambia `ODOO_EDITION`, ejecutá el preflight de solo lectura en cada entorno y no ejecutes operaciones funcionales desde el webhook.

## Comandos

```bash
ENTORNO=desarrollo make apply-image
ENTORNO=staging make restore SNAPSHOT=latest
ENTORNO=staging make repo-sync
ENTORNO=staging make build
ENTORNO=staging make apply-image
ENTORNO=staging make validate-image NOTE="regresión aprobada para el conjunto 19.0-stag"
```

Después de la validación, abrí el PR `19.0-stag → 19.0`. Su revisión cubre todo el delta validado; una feature adicional exige validar nuevamente el conjunto. Una vez fusionado y sincronizados los candidatos productivos, ejecutá `ENTORNO=produccion make promotion-verify` antes de construir la imagen de producción.

`apply-image` mueve Nueva a Actual y conserva la Actual previa en Anterior. Si una validación falla sin operaciones de módulos, ejecutá `rollback-image`. Si hubo operaciones de módulos, restaurá el backup asociado antes de recuperar la imagen.

Para Community→Enterprise, cambiá `ODOO_EDITION` y `TAG` en el `compose.env`, construí una Nueva Enterprise y validala progresivamente. En producción `apply-image` exige el backup asociado y conserva la imagen Community en Anterior; esa frontera no habilita un rollback ordinario hacia otra edición. Instalá o actualizá módulos Enterprise después de aplicar la imagen, de forma manual y con el backup preservado.

## Verificación

```bash
ENTORNO=<entorno> scripts/image-state.sh show
ENTORNO=<entorno> make verify
```

La procedencia y la nota de validación deben corresponder a la imagen ejecutada. `promotion-verify` debe confirmar que los árboles de todos los addons, la edición y la procedencia Enterprise de producción coinciden con la imagen Actual validada en staging.
