# Tasks: Gestión de ramas con staging

| Name | Code | Version | Date | Status |
| --- | --- | --- | --- | --- |
| gestion-ramas-staging | TASKS-004 | R00 | 2026-09-17 | Approved |

## Phase 1: US1 — Desarrollar addons localmente (P1)

- [x] T001 [US1] Adaptar `scripts/addons.sh` para eliminar la derivación de `19.0-dev`, aceptar `ADDONS_REF=feat/<nombre>` solo con `ENTORNO=desarrollo` y rechazar overrides en staging o producción.
- [x] T002 [TEST][US1] Actualizar `tests/test_addons.sh` para cubrir la sincronización local desde `feat/*`, el rechazo de refs inválidas y la ausencia de una rama operativa `19.0-dev`.
- [x] T003 [P][US1] Actualizar `docs/entorno/levantar-desarrollo.md` para documentar desarrollo local, la referencia explícita de feature y la ausencia de un runtime obligatorio de desarrollo en el servidor.

## Phase 2: US2 — Actualizar staging sin PR intermedio (P1)

- [x] T004 [US2] Adaptar `stacks/addons-webhook/app/server.py` para asignar únicamente `19.0-stag` a staging y `19.0` a producción, ignorando `19.0-dev` y `feat/*` sin mutar candidatos.
- [x] T005 [TEST][US2] Actualizar `tests/test_webhook_addons.sh` para afirmar la allowlist de dos ramas, la idempotencia de staging y la ausencia de cambios en Odoo o imágenes activas.
- [x] T006 [P][US2] Actualizar `docs/modulos/gestionar-catalogo-addons.md` y `docs/operacion/operar-webhook-addons.md` con las dos ramas de servidor, el push controlado a `19.0-stag` y los límites del receptor.

## Phase 3: US3 — Validar staging antes de promocionar (P1)

- [x] T007 [US3] Crear `scripts/promotion-verify.sh` para exigir una imagen Actual validada en `runtime/staging/state/images.json` y comparar sus árboles de addons, edición y procedencia Enterprise con los candidatos de producción.
- [x] T008 [TEST][US3] Crear `tests/test_promotion_verify.sh` con casos de validación exitosa, imagen de staging ausente o no validada, dominio faltante, árbol divergente y procedencia de edición incompatible.
- [x] T009 [P][US3] Actualizar `docs/entorno/levantar-staging.md` y `docs/modulos/validar-promocion.md` para describir la validación manual del conjunto completo de `19.0-stag` y su evidencia asociada a la imagen Actual.

## Phase 4: US4 — Promocionar producción mediante PR (P1)

- [x] T010 [US4] Actualizar `Makefile` para exponer `promotion-verify` bajo `ENTORNO=produccion` sin integrarlo a `build`, `apply-image` ni operaciones automáticas.
- [x] T011 [TEST][US4] Extender `tests/test_promotion_verify.sh` para comprobar que el target de `Makefile` exige producción, no construye imágenes ni promueve estado y falla si producción no equivale al staging validado.
- [x] T012 [P][US4] Actualizar `docs/entorno/levantar-produccion.md` para requerir `repo-sync` y `promotion-verify` después del PR `19.0-stag → 19.0` y antes del build productivo.

## Phase 5: US5 — Realinear staging (P1)

- [x] T013 [US5] Crear `docs/modulos/gestionar-ramas-staging.md` con el procedimiento Git manual para publicar features, promover `19.0-stag`, hacer avance rápido y realinear staging con `19.0` mediante una referencia de respaldo explícita.
- [x] T014 [TEST][US5] Extender `tests/test_addons.sh` para comprobar que una sincronización posterior a una realineación de `19.0-stag` reemplaza el candidato de staging y conserva aislados los candidatos de producción.
- [x] T015 [P][US5] Actualizar `docs/modulos/gestionar-fork.md`, `docs/modulos/especificacion-gestion-addons.md`, `ARCHITECTURE.md` y `README.md` con los roles de `feat/*`, `19.0-stag` y `19.0`, la promoción por PR y el significado de realinear staging.

## Phase 6: Integración y verificación

- [x] T016 [integration] Ejecutar `bash -n scripts/addons.sh scripts/promotion-verify.sh`, `make test` y `git diff --check`, corrigiendo únicamente los incumplimientos de `.specs/004-gestion-ramas-staging/spec.md`.
- [x] T017 [integration] Revisar `docs/entorno/levantar-desarrollo.md`, `docs/entorno/levantar-staging.md`, `docs/entorno/levantar-produccion.md` y `docs/modulos/gestionar-ramas-staging.md` para que los comandos descritos existan en `Makefile` o sean operaciones Git manuales explícitas.

## Verification

- [x] VERIFY Todos los escenarios de aceptación de `.specs/004-gestion-ramas-staging/spec.md` pasan.
- [x] VERIFY Todos los requisitos no funcionales de `.specs/004-gestion-ramas-staging/spec.md` se cumplen.
- [x] VERIFY Ningún principio MUST pertinente de `.specs/constitution.md` se vulnera.
- [x] VERIFY No se crean archivos fuera de los declarados en `.specs/004-gestion-ramas-staging/plan.md`.
- [x] VERIFY No se agregan dependencias fuera de las declaradas en `.specs/004-gestion-ramas-staging/plan.md`.

## Phase 7: Convergence

- [x] T018 Documentar y verificar en `docs/modulos/gestionar-ramas-staging.md` la política remota que rechaza force-push ordinario a `19.0-stag` y reserva la realineación para un procedimiento excepcional y auditable. [US2/AC3] (partial)
