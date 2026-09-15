# Reporte de correcciones — PR #15

PR: <https://github.com/Dipleg-SA/odoo-infrastructure/pull/15>

Base de comparación: `2981ad9c2ad2a7174a7f33c408a63667c69da9f6`

Rama: `codex/gestion-addons-inmutable`

## Resultado

Se corrigieron los ocho hallazgos del review y se agregaron regresiones
automatizadas para los casos que podían volver a romperse.

## Correcciones

- Backup: usa el Compose del entorno, escribe la métrica bajo su estado y conserva la procedencia actual de addons y Enterprise.
- `nuke`: elimina clones, builds y estado generado de `runtime/`, sin tocar configuraciones ni secretos.
- Observabilidad: `monitoring-role` lee el secreto y ejecuta Compose desde el contexto seleccionado.
- Dependencias: `pydeps` inspecciona los candidatos de `runtime/addons` y mantiene la raíz inyectada por el build.
- Webhook: `secrets-init` crea la firma y los cuatro archivos de credenciales bajo `runtime/control/secrets`.
- Estado de imágenes: valida las etiquetas antes de transicionar y escribe `compose.env` con una referencia segura.
- Documentación: se actualizaron las rutas de Enterprise y del webhook.

## Verificación

- `bash -n` sobre los scripts modificados: correcto.
- `make test`: 13/13 suites, 395 comprobaciones correctas.
- `git diff --check`: correcto.
- `ENTORNO=desarrollo make -n nuke`: confirma las rutas generadas de `runtime/` y conserva configs y secretos.

Los cambios locales ajenos a este PR se conservaron fuera del commit.
