# Validar una promoción

## Cuándo se usa

Antes de aplicar una imagen Nueva a un entorno o de continuarla hacia el siguiente.

## Objetivo

Dejar evidencia manual y conservar una reversión consistente.

## A mano

Validá la imagen en desarrollo, luego staging con datos restaurados de producción y finalmente producción. No ejecutes operaciones funcionales desde el webhook.

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

## Verificación

```bash
ENTORNO=<entorno> scripts/image-state.sh show
ENTORNO=<entorno> make verify
```

La procedencia y la nota de validación deben corresponder a la imagen ejecutada.
