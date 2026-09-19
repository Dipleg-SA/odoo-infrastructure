# Operar el webhook de addons

## Cuándo se usa

Para diagnosticar entregas GitHub y candidatos por entorno.

## Objetivo

Recibir únicamente pushes válidos y dejar disponible el candidato para una recreación
explícita.

## Flujo rápido

1. Revisar el receptor y su estado de candidatos.
2. Confirmar repositorio, rama y firma de la entrega.
3. Verificar que el webhook no haya construido, recreado ni operado módulos.

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
La entrega repetida es idempotente y el lock por entorno serializa webhook, build,
lifecycle y operaciones de módulos. El receptor escribe únicamente los tres destinos
custom; nunca monta Enterprise.

## Verificación

Confirmá el código HTTP y el estado del candidato. Un webhook válido no cambia
`ODOO_IMAGE`, contenedores, bases ni filestore. `odoo-verify` informa “pendiente de
recreación” mientras el inventario de arranque sea anterior. Build cuando corresponda,
recreación, validación funcional, módulos y promoción siguen siendo acciones manuales.
