# Operar el webhook de addons

## Cuándo se usa

Para diagnosticar entregas GitHub y candidatos por entorno.

## Objetivo

Recibir únicamente pushes válidos y dejar disponible el candidato para el próximo build.

## Flujo rápido

1. Revisar el receptor y su estado de candidatos.
2. Confirmar repositorio, rama y firma de la entrega.
3. Verificar que el webhook no haya cambiado imágenes ni runtimes.

## A mano

El endpoint público es `POST /webhooks/addons`. El receptor necesita solo el secreto de
firma, el catálogo, clones bare, candidatos y su estado. No recibe socket Docker, secretos
de Odoo, Enterprise ni acceso a la imagen.

## Comandos

```bash
ENTORNO=produccion stacks/addons-webhook/verify.sh
ENTORNO=staging make repo-status
ENTORNO=produccion make repo-status
```

Las ramas válidas en el servidor son `19.0-stag` y `19.0`. Una rama `feat/*` o
`19.0-dev`, un repositorio ausente del catálogo o el repositorio Enterprise se ignoran.
La entrega repetida es idempotente y el lock serializa webhook y build.

## Verificación

Confirmá el código HTTP y el estado del candidato. Un webhook válido no cambia
`ODOO_IMAGE`, contenedores, bases ni filestore; el cambio solo aparece en el build
siguiente. Build, validación funcional, módulos y promoción de código siguen siendo
acciones manuales.
