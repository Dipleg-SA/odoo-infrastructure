# Tasks: Imagen Odoo única por entorno

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| imagen-odoo-simple | TASKS-005 | R01 | 2026-09-17 | Approved |

## Fase 1: Preparación

- [x] T001 [setup] Confirmar que la implementación parte de la rama `005-imagen-odoo-simple` y conservar los cambios de trabajo preexistentes fuera del alcance de SPEC-005.

## Fase 2: Construir una única imagen seleccionada (US1) (P1)

- [x] T002 [US1] Reemplazar los tags `bootstrap` y las instrucciones de promoción en `runtime/desarrollo/compose.env.example`, `runtime/staging/compose.env.example` y `runtime/produccion/compose.env.example` por el selector único `ODOO_IMAGE`.
- [x] T003 [US1] Adaptar `scripts/build-odoo-image.sh` para derivar un tag explícito por build, construirlo y actualizar atómicamente el `ODOO_IMAGE` del `compose.env` solo después de obtener una identidad Docker válida.
- [x] T004 [US1] Adaptar `Makefile` para que `build` construya la imagen Odoo y las imágenes propias auxiliares sin depender de `image-state.sh` ni exponer targets de promoción o rollback.
- [x] T005 [US1] Mantener en `stacks/odoo/compose.yaml` el consumo directo del único `ODOO_IMAGE` y actualizar sus comentarios para describir el contrato nuevo.
- [x] T006 [TEST][US1] Actualizar `tests/test_build_odoo_image.sh` para cubrir la escritura atómica del selector, la conservación del selector ante un build fallido y la separación entre los tres entornos.

## Fase 3: Levantar Odoo sin promoción ni rollback (US2) (P1)

- [x] T007 [US2] Eliminar `scripts/image-state.sh` y retirar de `Makefile` `apply-image`, `rollback-image`, `validate-image` y las guardas de transición que dependan de sus ranuras.
- [x] T008 [US2] Adaptar `Makefile` para que `up` y `odoo-up` validen, antes de invocar Compose para Odoo, que `ODOO_IMAGE` está definida, no es bootstrap ni flotante y corresponde a una imagen local existente; ante un fallo deben detenerse con una causa operativa identificable.
- [x] T009 [US2] Adaptar `scripts/odoo-module-operation.sh` para exigir un runtime Odoo configurado y operativo, sin exigir una imagen `Actual` ni registrar bloqueos de rollback.
- [x] T010 [US2] Adaptar `scripts/odoo-edition-check.sh` para comprobar la compatibilidad Community/Enterprise desde la configuración y la base vigente, sin leer `images.json`.
- [x] T011 [TEST][US2] Actualizar `tests/test_scripts.sh`, `tests/test_addon_operations.sh` y `tests/test_edition_transition.sh` para cubrir la guarda previa de `up` y `odoo-up`, comprobar mediante stubs que Compose no se invoca con una referencia inválida y cubrir operaciones de módulos y cambios de edición con el selector único.
- [x] T012 [TEST][US2] Eliminar `tests/test_image_state.sh` y retirar del resto de la suite cualquier fixture o aserción que dependa de `Nueva`, `Actual`, `Anterior` o `rollback_blocked`.

## Fase 4: Usar el mismo ciclo en los tres entornos (US3) (P1)

- [x] T013 [US3] Adaptar `scripts/promotion-verify.sh` para comparar candidatos, edición y procedencia de código de staging y producción sin exigir una imagen `Actual` ni `runtime/staging/state/images.json`.
- [x] T014 [US3] Adaptar `stacks/backup/scripts/backup.sh`, `stacks/backup/scripts/restore.sh` y `stacks/backup/verify.sh` para conservar base y filestore, ignorar metadatos legacy de slots de imagen y no restaurar selecciones de imágenes.
- [x] T015 [TEST][US3] Actualizar `tests/test_backup.sh` para cubrir backups y restores nuevos, la tolerancia ante metadatos legacy y la ausencia de dependencia operativa de `images.json`.
- [x] T016 [TEST][US3] Actualizar `tests/test_promotion_verify.sh` para cubrir la comparación de candidatos y edición sin estado de imágenes.

## Fase 5: Levantar el runtime por orden de stacks (US4) (P1)

- [x] T017 [US4] Reorganizar `docs/entorno/levantar-desarrollo.md`, `docs/entorno/levantar-staging.md` y `docs/entorno/levantar-produccion.md` con las fases comunes Edge → PostgreSQL → Odoo → Backup → Monitoring. Cada fase aplicable debe indicar su target de levantamiento y su verificación antes de continuar; en particular, `postgres-verify` debe terminar correctamente antes de ejecutar `odoo-up`.
- [x] T018 [US4] Actualizar `docs/backup-restore/restore-staging.md` y `docs/backup-restore/restore-perdida-total.md` para ubicar restore, reconstrucción y levantamiento dentro del orden de stacks nuevo.
- [x] T019 [TEST][US4] Agregar a `tests/test_architecture.sh` aserciones que detecten el orden de fases, comprueben que `postgres-up` y `postgres-verify` aparecen antes de `odoo-up`, y validen que los stacks no incluidos se declaran como no aplicables.

## Fase 6: Verificar sin estado de promoción (US5) (P1)

- [x] T020 [US5] Adaptar `stacks/odoo/verify.sh` para informar la única referencia `ODOO_IMAGE` efectiva, comprobar su existencia local y su procedencia técnica, y fallar ante una referencia ausente, bootstrap, flotante o distinta de la imagen configurada en Compose, sin consultar `images.json`.
- [x] T021 [TEST][US5] Actualizar `tests/test_verify.sh` para cubrir todas las ramas de validación de `ODOO_IMAGE` mediante stubs, y `tests/test_docker_smoke.sh` para comprobar con Docker real que Compose usa la referencia seleccionada y que no depende de `images.json`.

## Fase 7: Documentación y contratos transversales

- [x] T022 [P][DOCS] Actualizar `ARCHITECTURE.md` y `docs/modulos/especificacion-gestion-addons.md` para eliminar la máquina de estados de imágenes y describir el selector único, la recuperación por backup y la reconstrucción explícita.
- [x] T023 [P][DOCS] Actualizar `docs/modulos/construir-y-aplicar-imagen.md`, `docs/modulos/gestionar-enterprise.md`, `docs/modulos/gestionar-fork.md`, `docs/modulos/gestionar-modulo.md`, `docs/modulos/gestionar-ramas-staging.md` y `docs/modulos/validar-promocion.md` para usar `build`, levantamiento y validación sin promoción de imagen.
- [x] T024 [P][DOCS] Actualizar `docs/operacion/operar-backups.md`, `docs/operacion/operar-odoo.md` y `docs/operacion/operar-webhook-addons.md` para retirar referencias a slots, rollback, `apply-image` e `images.json` operativo.
- [x] T025 [P][DOCS] Actualizar `docs/backup-restore/migrar-deployment-externo.md`, `docs/credenciales/rotar-credenciales-r2.md`, `docs/credenciales/rotar-token-cloudflare-tunnel.md` y `docs/credenciales/rotar-token-git.md` para retirar instrucciones obsoletas vinculadas al ciclo de imágenes.

## Verificación

- [x] VERIFY Ejecutar `bash -n` sobre `scripts/build-odoo-image.sh`, `scripts/odoo-edition-check.sh`, `scripts/odoo-module-operation.sh`, `scripts/promotion-verify.sh`, los scripts de backup modificados y los tests modificados.
- [x] VERIFY Ejecutar `make test` y confirmar que todos los tests terminan, sin dejar procesos pendientes.
- [ ] VERIFY Ejecutar `docker compose config` para desarrollo, staging y producción con sus perfiles requeridos y confirmar que cada composición conserva sus servicios y redes esperados.
- [ ] VERIFY Ejecutar un build y levantamiento real de desarrollo respetando el orden documentado, ejecutar la verificación correspondiente después de cada stack y confirmar que `postgres-verify` termina correctamente antes de `odoo-up`; finalizar con `make verify`.
- [ ] VERIFY Comprobar staging y producción con sus procedimientos de restore, backup, timers, promoción de código y monitoring, sin exigir `images.json` ni rollback de imagen.
- [x] VERIFY Confirmar todos los escenarios de aceptación y NFR de `spec.md`.
- [x] VERIFY Confirmar que ningún MUST de `.specs/constitution.md` queda incumplido y que no se agregaron dependencias nuevas.
- [x] VERIFY Confirmar que no se crearon archivos fuera de la estructura aprobada en `plan.md`.
