# Spec: Gestión de ramas con staging

| Name | Code | Version | Date | Status |
| --- | --- | --- | --- | --- |
| gestion-ramas-staging | SPEC-004 | R00 | 2026-09-17 | Approved |

## Summary

Definir un flujo de addons con desarrollo local en `feat/*`, validación compartida en `19.0-stag` y producción protegida en `19.0`, sin una rama operativa `19.0-dev` ni un PR obligatorio para entrar a staging.

## Clarifications

| Decisión | Contrato |
| --- | --- |
| Ubicación de desarrollo | `feat/*` se trabaja en la máquina del desarrollador. No existe un entorno de desarrollo operativo obligatorio en el servidor. |
| Rama de staging | `19.0-stag` vive en el remoto y representa el contenido que debe probarse en staging. |
| Entrada a staging | Una feature llega a `19.0-stag` mediante un push o merge controlado; no requiere un PR contra staging. |
| Promoción a producción | La promoción se realiza mediante un PR de `19.0-stag` hacia `19.0`, después de validar staging. |
| Limpieza de staging | Si staging acumula cambios descartables, se realinea para que coincida exactamente con `19.0`; la operación no se denomina rebase. |
| Varios cambios | `19.0-stag` puede contener varias features, pero una promoción incluye todo su delta respecto de `19.0` y exige validar el conjunto completo. |
| Automatización | La sincronización de candidatos puede ser automática; el build, la aplicación de imágenes, la validación funcional y la promoción siguen siendo decisiones manuales. |

## Success Metrics

N/A: el resultado se mide por los escenarios de aceptación y por la eliminación de la rama operativa `19.0-dev`.

## User Stories

### US1 — Desarrollar addons localmente (P1)

Como desarrollador, quiero trabajar en ramas `feat/*` desde mi máquina local, para no depender de un entorno de desarrollo en el servidor.

**Acceptance Scenarios**:

- **Given** un repositorio de addons con `19.0` y `19.0-stag`, **when** se inicia un cambio, **then** el trabajo se realiza en una rama `feat/*` local sin modificar `19.0`.
- **Given** una rama `feat/*` local, **when** se ejecutan las pruebas de desarrollo, **then** no se requiere un runtime de desarrollo en el servidor.

### US2 — Actualizar staging sin PR intermedio (P1)

Como operador, quiero publicar una feature seleccionada en `19.0-stag` sin abrir un PR adicional, para probarla rápidamente en staging.

**Acceptance Scenarios**:

- **Given** una rama `feat/*` lista para probar, **when** se publica de forma controlada sobre `19.0-stag`, **then** la rama de staging queda en el commit esperado y `19.0` no cambia.
- **Given** un push válido a `19.0-stag`, **when** se sincronizan los addons, **then** solo se actualiza el candidato de staging y no se reinician contenedores ni se modifica la imagen activa automáticamente.
- **Given** un intento de sobrescribir cambios no evaluados de `19.0-stag`, **when** la actualización no es un avance compatible, **then** falla y no reemplaza silenciosamente la rama remota.

### US3 — Validar staging antes de promocionar (P1)

Como operador, quiero que staging represente el estado candidato de la rama `19.0-stag`, para decidir si ese conjunto puede llegar a producción.

**Acceptance Scenarios**:

- **Given** una revisión actualizada en `19.0-stag`, **when** se construye y aplica manualmente la imagen de staging, **then** la imagen contiene exactamente los commits candidatos de esa rama.
- **Given** una validación funcional fallida, **when** se revisa el estado de Git, **then** no se puede promocionar automáticamente `19.0-stag` a `19.0`.
- **Given** una validación funcional exitosa, **when** se registra la aprobación, **then** quedan identificados el commit de staging y la imagen validada.

### US4 — Promocionar producción mediante PR (P1)

Como operador, quiero promover a producción únicamente el estado validado de staging, para mantener `19.0` como rama estable.

**Acceptance Scenarios**:

- **Given** `19.0-stag` validada, **when** se abre un PR de `19.0-stag` hacia `19.0`, **then** el PR representa todo el delta validado entre ambas ramas.
- **Given** un PR de promoción aprobado y fusionado, **when** producción sincroniza `19.0`, **then** recibe el contenido promovido sin incluir cambios que no estaban en staging.
- **Given** una `19.0-stag` no validada, **when** se intenta promoverla, **then** el procedimiento exige detener la promoción y completar la validación.

### US5 — Realinear staging (P1)

Como operador, quiero descartar el ruido acumulado en staging y devolverla al estado productivo, para comenzar una nueva validación desde una base conocida.

**Acceptance Scenarios**:

- **Given** que `19.0-stag` contiene commits que no deben promoverse, **when** el operador decide descartarlos, **then** `19.0-stag` vuelve a coincidir exactamente con `19.0`.
- **Given** una realineación completada, **when** se inicia una nueva feature, **then** ningún commit descartado aparece en la nueva promoción.
- **Given** que `19.0-stag` está detrás de `19.0` sin divergencias, **when** se actualiza, **then** avanza sin reescribir historial innecesariamente.

## Non-Functional Requirements

- **MUST**: El flujo no debe requerir una rama operativa `19.0-dev`.
- **MUST**: Ningún push o sincronización de `19.0-stag` debe aplicar automáticamente una imagen, reiniciar Odoo ni operar módulos.
- **MUST**: La promoción a `19.0` debe conservar el SHA o la procedencia equivalente del estado validado en staging.
- **MUST**: La realineación de `19.0-stag` debe ser explícita, reversible mediante Git y no ejecutarse como reacción automática a un webhook.
- **SHOULD**: El flujo debe conservar los comandos existentes de sincronización, build, aplicación y verificación, cambiando solo su selección de rama y documentación cuando sea necesario.

## Edge Cases

- Si `19.0-stag` avanzó desde que se creó una `feat/*`, la publicación debe detenerse hasta integrar conscientemente la base actual o realinear staging.
- Si staging contiene varias features, la validación y el PR de promoción deben cubrir el conjunto completo, no solo la última feature agregada.
- Si la validación falla, el operador puede corregir la feature y actualizar staging, o realinear staging con `19.0` y comenzar nuevamente.
- Si un cambio afecta varios repositorios de addons, todos sus commits deben formar parte del mismo estado de staging validado antes de promover.
- Si el commit promovido a `19.0` no coincide con el estado validado, la promoción debe detenerse y requerir una nueva validación.

## Assumptions & Dependencies

- El webhook existente puede seguir sincronizando candidatos desde pushes a `19.0-stag` y `19.0`.
- Staging y producción continúan ejecutándose en el servidor con sus runtimes actuales.
- La validación funcional de staging permanece manual.
- La infraestructura de Compose, los volúmenes y los mecanismos de backup quedan fuera de esta especificación.

## Explicit Non-Goals

- Crear o mantener un runtime de desarrollo obligatorio en el servidor.
- Exigir un PR individual de `feat/*` hacia `19.0-stag`.
- Probar varios entornos de staging en paralelo.
- Automatizar la aplicación de imágenes, la validación funcional o las operaciones de módulos.
- Rediseñar Compose, redes, volúmenes, backups o la arquitectura de stacks.

## Open Questions
