# Tasks: Edición Community o Enterprise

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| Edición Community o Enterprise | TASKS-002 | R00 | 2026-09-16 | Approved |

## Phase 1: Setup y contrato de configuración

- [x] T001 [US1] Agregar a `scripts/lib/contexto.sh` la carga, exportación y validación de `ODOO_EDITION` y `TAG`, incluyendo la correspondencia entre edición y prefijo `19.0-ce-` o `19.0-ee-`.
- [x] T002 [P][US1] Actualizar `runtime/desarrollo/compose.env.example` con la configuración plana Community (`ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`).
- [x] T003 [P][US1] Actualizar `runtime/staging/compose.env.example` con la configuración plana Community (`ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`).
- [x] T004 [P][US1] Actualizar `runtime/produccion/compose.env.example` con la configuración plana Community (`ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`).
- [x] T005 [TEST][US1] Extender `tests/test_compose.sh` para comprobar configuración plana válida de Community y Enterprise y rechazar edición ausente, valor inválido, tag ausente, formato inválido y prefijo incompatible; actualizar los fixtures de `tests/test_contextos.sh`, `tests/test_addon_operations.sh`, `tests/test_addons.sh`, `tests/test_backup.sh`, `tests/test_build_odoo_image.sh`, `tests/test_report_config.sh` y `tests/test_scripts.sh` para declarar el contrato requerido.

## Phase 2: US2 — Construir una imagen Community (P1)

- [x] T006 [US2] Implementar en `scripts/build-odoo-image.sh` la rama Community sin exigir checkout, credencial ni tag Enterprise, ignorando cualquier checkout residual.
- [x] T007 [US2] Registrar en `scripts/build-odoo-image.sh` la procedencia Community con `edition`, `edition_tag`, digest, línea de Odoo, commit de infraestructura, commits de addons y momento de construcción.
- [x] T008 [P][US2] Ajustar `stacks/odoo/image/Dockerfile` para aceptar el contexto Enterprise vacío utilizado por el build Community sin incorporar código privado.
- [x] T009 [P][US2] Ajustar `stacks/odoo/image/entrypoint.sh` para agregar Enterprise al `addons_path` únicamente cuando existan manifiestos Enterprise válidos.
- [x] T010 [TEST][US2] Agregar en `tests/test_build_odoo_image.sh` un escenario Community con checkout Enterprise residual y verificar que la imagen y sus metadatos no lo incorporen.

## Phase 3: US3 — Construir una imagen Enterprise (P1)

- [x] T011 [US3] Adaptar `scripts/addons.sh` para resolver el tag Enterprise desde `TAG`, conservar compatibilidad con la invocación positional existente y validar el tag anotado e inmutable.
- [x] T012 [US3] Implementar en `scripts/build-odoo-image.sh` la rama Enterprise con checkout limpio, tag coherente con `TAG`, commit resoluble y publicación atómica de `Nueva` solo después del digest.
- [x] T013 [US3] Completar en `scripts/build-odoo-image.sh` la procedencia Enterprise con `enterprise_tag`, `enterprise_commit` y `enterprise_modules` derivados de manifiestos técnicos, manteniendo la separación del checkout privado.
- [x] T014 [TEST][US3] Extender `tests/test_build_odoo_image.sh` para cubrir checkout o tag ausente, tag liviano, tag inexistente, checkout inconsistente y build Enterprise válido.
- [x] T015 [TEST][US3] Extender `tests/test_addons.sh` para comprobar que `TAG` selecciona el candidato Enterprise correcto y que los errores no publican un candidato parcial.

## Phase 4: US4 — Promover y revertir sin mezclar ediciones (P1)

- [x] T016 [US4] Extender `scripts/image-state.sh` con `edition`, `edition_tag` y los campos Enterprise opcionales u obligatorios según la edición, incluyendo inferencia de estados históricos Enterprise.
- [x] T017 [US4] Agregar en `scripts/image-state.sh` las guardas de edición para `verify`, `apply-image`, `rollback-image`, rotación de `Nueva`/`Actual`/`Anterior` y sincronización del selector de Compose.
- [x] T018 [P][US4] Actualizar `stacks/odoo/verify.sh` para comparar edición, tag, digest y procedencia de la imagen activa con el runtime configurado.
- [x] T019 [P][US4] Actualizar `Makefile` para detectar un cambio de edición antes de `apply-image`, conservar el backup previo de producción y exponer la guarda sin cambiar el propósito de `build`, `rollback-image` y `verify`.
- [x] T020 [TEST][US4] Extender `tests/test_image_state.sh` con estados Community y Enterprise, mismatch de ranuras, promoción válida, rollback cruzado bloqueado e inferencia histórica.
- [x] T021 [TEST][US4] Extender `tests/test_verify.sh` para comprobar que `verify` detecta una imagen activa de edición distinta y una procedencia inconsistente.

## Phase 5: US5 — Pasar de Community a Enterprise (P1)

- [x] T022 [US5] Crear `scripts/odoo-edition-check.sh` con la interfaz `ENTORNO=<entorno> scripts/odoo-edition-check.sh --destino <community|enterprise>`, consulta ORM de solo lectura, salida de módulos detectados y códigos `0` compatible, `1` bloqueado y `2` error.
- [x] T023 [US5] Integrar en `scripts/image-state.sh` y `stacks/backup/scripts/backup.sh` el preflight Community→Enterprise, el requisito de backup previo de producción, la metadata atómica `runtime/<entorno>/state/meta/last-backup.json` y el registro de la edición destino sin ejecutar operaciones funcionales.
- [x] T024 [P][US5] Documentar en `docs/modulos/construir-y-aplicar-imagen.md` el build Enterprise, la validación progresiva y la aplicación manual posterior de módulos.
- [x] T025 [P][US5] Documentar en `docs/modulos/validar-promocion.md` la transición Community→Enterprise como frontera de rollback y sus validaciones.
- [x] T026 [P][US5] Actualizar `docs/entorno/levantar-desarrollo.md` con el cambio de edición mediante configuración plana y validación aislada.
- [x] T027 [P][US5] Actualizar `docs/entorno/levantar-staging.md` con el flujo de validación Community→Enterprise antes de producción.
- [x] T028 [P][US5] Actualizar `docs/entorno/levantar-produccion.md` con el backup obligatorio y la aplicación controlada de una transición de edición.
- [x] T029 [TEST][US5] Agregar en `tests/test_edition_transition.sh` escenarios Community→Enterprise que verifiquen backup asociado, preflight de solo lectura, conservación de módulos Community, ausencia de cambios funcionales automáticos y recuperación por imagen anterior antes de operar módulos.

## Phase 6: US6 — Pasar de Enterprise a Community (P1)

- [ ] T030 [US6] Completar en `scripts/odoo-edition-check.sh` el bloqueo Enterprise→Community cuando la intersección entre módulos instalados y `enterprise_modules` no sea vacía, bloquear también si falta inventario histórico y permitir continuar solo con una base validada sin ellos.
- [ ] T031 [US6] Completar en `scripts/image-state.sh` la guarda Enterprise→Community, evitando activar una imagen Community contra una base incompatible y conservando el backup asociado.
- [ ] T032 [P][US6] Actualizar `docs/modulos/gestionar-enterprise.md` con el retiro manual de módulos Enterprise, la variante Community y la prohibición de conversión automática.
- [ ] T033 [P][US6] Actualizar `docs/backup-restore/restore-staging.md` con la restauración de una copia sin módulos Enterprise para validar el destino Community.
- [ ] T034 [P][US6] Actualizar `docs/backup-restore/restore-perdida-total.md` con la procedencia de edición y la recuperación segura de una transición Enterprise→Community.
- [ ] T035 [TEST][US6] Completar `tests/test_edition_transition.sh` con base bloqueada por módulos Enterprise, base permitida sin ellos, backup asociado y rechazo de rollback cruzado.

## Phase 7: US7 — Restaurar y conservar compatibilidad histórica (P2)

- [ ] T036 [TEST][US7] Agregar en `tests/test_image_state.sh` un estado Enterprise histórico sin `edition` y comprobar que se normaliza al leerlo sin exigir una reescritura manual de sus metadatos.
- [ ] T037 [P][US7] Actualizar `docs/README.md` con el contrato único de `ODOO_EDITION` y `TAG`, incluyendo la migración de la documentación v2 a `docs/`.
- [ ] T038 [P][US7] Actualizar `docs/modulos/especificacion-gestion-addons.md` para incluir la edición en la fotografía, candidatos, promoción y restauración.
- [ ] T039 [P][US7] Actualizar `docs/backup-restore/migrar-deployment-externo.md` para seleccionar Community o Enterprise y conservar la procedencia correspondiente.
- [ ] T040 [TEST][US7] Extender `tests/test_backup.sh` para ejecutar backup y restore de una fotografía Community nueva, conservar `edition` y `edition_tag` en `images.json` y comprobar que no se intenta recuperar código Enterprise.

## Verification

- [ ] VERIFY Ejecutar `make test` y comprobar todos los escenarios de aceptación de `spec.md`, incluidos ambos sentidos de transición.
- [ ] VERIFY Ejecutar `bash -n` sobre `scripts/lib/contexto.sh`, `scripts/addons.sh`, `scripts/build-odoo-image.sh`, `scripts/image-state.sh`, `scripts/odoo-edition-check.sh`, `stacks/odoo/image/entrypoint.sh`, `stacks/odoo/verify.sh` y los scripts de test modificados.
- [ ] VERIFY Ejecutar las pruebas de Compose y verificar que cada runtime resuelva la misma edición y tag configurados, sin activar perfiles adicionales.
- [ ] VERIFY Comprobar con `docker compose config` que los cambios no incorporen Enterprise en Community y que el selector de imagen conserve la edición promovida.
- [ ] VERIFY Confirmar que `images.json`, backups y restores conservan edición, tag, digest, procedencia y campos Enterprise según corresponda.
- [ ] VERIFY Confirmar que ningún preflight modifica módulos, registros funcionales o datos de la base y que las operaciones de módulos siguen siendo manuales.
- [ ] VERIFY Confirmar que no se modificaron archivos privados `runtime/*/compose.env`, checkout Enterprise ni secretos, y que no se agregaron dependencias fuera de `plan.md`.
- [ ] VERIFY Confirmar que no se viola ningún principio `MUST` de `.specs/constitution.md` y que la documentación operativa permanece en español.
