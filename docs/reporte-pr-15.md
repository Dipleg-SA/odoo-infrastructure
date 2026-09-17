# Documento histórico: reporte de correcciones — PR #15

Este documento conserva el contexto de PR #15 y no es un procedimiento operativo
vigente. Para la arquitectura actual, consultar `README.md`, `ARCHITECTURE.md` y los
runbooks bajo `docs/`.

PR: <https://github.com/Dipleg-SA/odoo-infrastructure/pull/15>

Base de comparación: `2981ad9c2ad2a7174a7f33c408a63667c69da9f6`

Rama: `codex/gestion-addons-inmutable`

## Resultado

Se corrigieron los ocho hallazgos del review y se agregaron regresiones
automatizadas para los casos que podían volver a romperse.

## Correcciones

- Backup: usa el Compose del entorno, escribe la métrica bajo su estado y conserva la procedencia actual de addons y Enterprise.
- `nuke`: elimina candidatos, builds y estado generado solo del entorno seleccionado; conserva clones bare compartidos, Enterprise, otros entornos, control, configuraciones y secretos.
- Observabilidad: `monitoring-role` lee el secreto y ejecuta Compose desde el contexto seleccionado.
- Dependencias: `pydeps` inspecciona los candidatos de `runtime/addons` y mantiene la raíz inyectada por el build.
- Webhook: `secrets-init` crea la firma y los cuatro archivos de credenciales bajo `runtime/control/secrets`.
- Estado de imágenes: valida las etiquetas antes de transicionar y escribe `compose.env` con una referencia segura.
- Documentación: se actualizaron las rutas de Enterprise y del webhook.

## Verificación

- `bash -n` sobre los scripts modificados: correcto.
- `make test`: 13/13 suites, 395 comprobaciones correctas.
- `git diff --check`: correcto.
- `ENTORNO=desarrollo make -n nuke`: confirma las rutas del entorno seleccionado y conserva recursos compartidos, configs y secretos.

Los cambios locales ajenos a este PR se conservaron fuera del commit.
