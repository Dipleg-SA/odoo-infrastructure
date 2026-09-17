# Tareas: Correcciones integrales del backlog

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| Correcciones integrales del backlog | TASKS-003 | R00 | 2026-09-17 | Draft |

## Fase 1: Preparación

- [x] T001 [setup] Confirmar que `.specs/003-correcciones-backlog/spec.md`, `.specs/003-correcciones-backlog/plan.md` y `.specs/backlog.md` están presentes y que el working tree no contiene cambios ajenos a esta feature.

## Fase 2: US1 — Mantener contratos y documentación vigentes (P1)

- [x] T002 [US1] Actualizar `README.md` y `ARCHITECTURE.md` para describir `runtime/addons/catalogo.txt`, el layout actual de addons y el inventario vigente de stacks (B001, B023).
- [x] T003 [P][US1] Migrar `docs/modulos/gestionar-fork.md`, `docs/modulos/gestionar-catalogo-addons.md` y `docs/modulos/especificacion-gestion-addons.md` a las rutas `runtime/addons` y a la selección de edición vigente (B002).
- [x] T004 [P][US1] Reconciliar `docs/modulos/gestionar-enterprise.md`, `docs/backup-restore/restore-perdida-total.md`, `docs/backup-restore/restore-staging.md` y `docs/backup-restore/migrar-deployment-externo.md` para eliminar el flujo obsoleto por ZIP y cubrir Community y Enterprise (B003, B004).
- [x] T005 [P][US1] Actualizar `docs/modulos/construir-y-aplicar-imagen.md`, `docs/modulos/validar-promocion.md`, `docs/entorno/levantar-desarrollo.md`, `docs/entorno/levantar-staging.md` y `docs/entorno/levantar-produccion.md` con `runtime/<entorno>/compose.env`, `ODOO_EDITION` y `TAG` (B015).
- [x] T006 [P][US1] Documentar `runtime/control`, sus dependencias de bootstrap y la recuperación de estado en `docs/README.md`, `docs/backup-restore/realizar-backup.md`, `docs/backup-restore/restore-perdida-total.md` y `docs/operacion/operar-backups.md`; aislar el fallback legacy en `stacks/backup/scripts/restore.sh` (B016, B018, B039).
- [x] T007 [P][US1] Actualizar `docs/operacion/configurar-docker-host.md` y `docs/README.md` para distinguir `make test`, `make verify` y el cliente Docker Compose requerido (B007, B036).
- [x] T008 [US1] Marcar `docs/reporte-pr-15.md` como histórico y eliminar instrucciones ejecutables legacy de `README.md`, `PRINCIPLES.md`, `ARCHITECTURE.md` y los documentos afectados, conservando contexto histórico solo donde corresponda (B037).
- [x] T009 [US1] Retirar `CHANGELOG.md` y dejar en `README.md` y `CONTRIBUTING.md` la política de registrar cambios en releases, sin crear un changelog alternativo (B035).
- [x] T010 [US1] Retirar o justificar en `.gitignore` las reglas legacy de `addons/` y `state/` que contradigan el modelo operativo bajo `runtime/`, sin borrar directorios existentes (B034).
- [x] T011 [TEST][US1] Ampliar `tests/test_architecture.sh` y `tests/test_compose.sh` para detectar rutas legacy ejecutables, verificar el layout documentado y comprobar que la selección de edición usa solo `ODOO_EDITION` y `TAG` (B001, B015, B023).

## Fase 3: US2 — Operar con límites seguros y consistentes (P1)

- [x] T012 [US2] Fortalecer `scripts/verify-host.sh` para validar JSON y comprobar `log-driver`, `max-size` y `max-file` contra `host/daemon.json` antes de declarar el host listo (B005).
- [x] T013 [US2] Alinear el contrato de `host-init` en `Makefile` con `scripts/verify-host.sh`, incluyendo mensajes accionables cuando la configuración existente no puede reemplazarse de forma segura (B006).
- [x] T014 [P][US2] Definir dependencia de red, timeout y errores verificables en `host/systemd/notify@.service` y `scripts/failure-notify.sh` (B008).
- [x] T015 [US2] Integrar `scripts/integrity-check.sh` con `scripts/lib/contexto.sh`, exponer `integrity-check` desde `Makefile` y mantener el chequeo sobre la composición del `ENTORNO` seleccionado (B009).
- [x] T016 [US2] Aislar los nombres one-off y el lock de operaciones de módulos en `scripts/odoo-module-operation.sh`, `scripts/lib/candidate-lock.sh` y `scripts/timers.sh` por proyecto y entorno (B010).
- [x] T017 [P][US2] Hacer que `scripts/pydeps.sh` exija el contexto del runtime y falle ante manifiestos inválidos, sin volver al fallback operativo de `addons/` legacy (B011, B013).
- [x] T018 [P][US2] Actualizar `scripts/vscode-workspace.sh` para generar folders desde `runtime/addons` y conservar el workspace de infraestructura sin duplicar árboles (B012).
- [x] T019 [TEST][US2] Ampliar `tests/test_scripts.sh`, `tests/test_contextos.sh`, `tests/test_pydeps.sh` y `tests/test_verify.sh` para cubrir host, integrity, aislamiento, manifiestos inválidos, workspace y notificaciones fallidas (B007, B009, B010, B011, B012, B013, B014).
- [x] T020 [US2] Reconciliar la retención de Loki entre `stacks/loki/config/loki.yaml`, `stacks/loki/compose.yaml` y `stacks/loki/verify.sh`, dejando un valor efectivo único y comprobable (B019).
- [x] T021 [US2] Ejecutar `stacks/addons-webhook` con usuario no privilegiado y permisos mínimos en `stacks/addons-webhook/compose.yaml`, ajustando `stacks/addons-webhook/verify.sh` al contrato resultante (B020).
- [x] T022 [US2] Documentar y endurecer los montajes privilegiados de Alloy en `stacks/alloy/compose.yaml`, `stacks/alloy/verify.sh` y `stacks/alloy/scripts/monitoring-role.sh`, manteniendo solo los accesos necesarios para observabilidad (B021).
- [x] T023 [US2] Agregar validaciones de perfiles inactivos en `scripts/verify-stacks.sh`, `stacks/certbot/verify.sh`, `stacks/dnsmasq/verify.sh` y `stacks/backup/verify.sh` para `cert`, `lan` y `restore` (B022).
- [x] T024 [US2] Registrar `addons-webhook` en `STACKS` y asociar `repo-sync` y `repo-status` a una agrupación visible en `.make/main.mk` y `Makefile`, generando el sexteto uniforme de targets del webhook mediante `stacks/addons-webhook/compose.yaml` (B032, B033).
- [x] T025 [P][US2] Normalizar los bloques de comentarios de `stacks/addons-webhook/compose.yaml`, `stacks/addons-webhook/verify.sh`, `stacks/alloy/compose.yaml`, `stacks/alloy/verify.sh`, `stacks/alloy/scripts/monitoring-role.sh`, `stacks/backup/compose.yaml`, `stacks/backup/verify.sh`, `stacks/backup/scripts/backup.sh`, `stacks/backup/scripts/restore.sh`, `stacks/certbot/compose.yaml`, `stacks/certbot/verify.sh`, `stacks/certbot/scripts/cert.sh`, `stacks/certbot/scripts/wrapper.sh`, `stacks/cloudflared/compose.yaml` y `stacks/cloudflared/verify.sh` al formato obligatorio (B024).
- [x] T026 [P][US2] Normalizar los bloques de comentarios de `stacks/dnsmasq/compose.yaml`, `stacks/dnsmasq/verify.sh`, `stacks/grafana/compose.yaml`, `stacks/grafana/verify.sh`, `stacks/loki/compose.yaml`, `stacks/loki/verify.sh`, `stacks/nginx/compose.yaml`, `stacks/nginx/verify.sh`, `stacks/odoo/compose.yaml`, `stacks/odoo/verify.sh`, `stacks/odoo/image/entrypoint.sh`, `stacks/postgres/compose.yaml`, `stacks/postgres/verify.sh`, `stacks/prometheus/compose.yaml` y `stacks/prometheus/verify.sh` al formato obligatorio (B024).
- [x] T027 [TEST][US2] Ampliar `tests/test_webhook_addons.sh`, `tests/test_compose.sh`, `tests/test_verify.sh` y `tests/test_verify_stacks.sh` para probar los targets del webhook, los límites de privilegio, los perfiles y la diferencia entre stack ausente y servicio caído (B017, B020–B022, B032, B033).

## Fase 4: US3 — Conservar una suite confiable y reproducible (P1)

- [x] T028 [US3] Hacer herméticos `tests/test_build_odoo_image.sh`, `tests/test_image_state.sh` y `tests/test_backup.sh`, reemplazando la eliminación de estado ignorado por checkouts temporales y snapshots byte a byte (B025).
- [x] T029 [US3] Agregar cobertura directa para `stacks/addons-webhook/verify.sh`, `stacks/alloy/verify.sh`, `stacks/backup/verify.sh`, `stacks/certbot/verify.sh`, `stacks/cloudflared/verify.sh`, `stacks/dnsmasq/verify.sh`, `stacks/grafana/verify.sh`, `stacks/loki/verify.sh`, `stacks/nginx/verify.sh`, `stacks/odoo/verify.sh`, `stacks/postgres/verify.sh` y `stacks/prometheus/verify.sh` desde `tests/test_verify_stacks.sh`, conservando en `scripts/verify-stacks.sh` la diferencia entre stack no declarado, servicio caído y expectativa incumplida (B026).
- [x] T030 [P][US3] Hacer que `tests/stubs/docker` y `tests/stubs/systemctl` fallen por defecto cuando falta un fixture, documentando cada respuesta sintética requerida por las pruebas (B029).
- [x] T031 [P][US3] Agregar aserciones de exit code y salida a `tests/test_scripts.sh`, `tests/test_contextos.sh`, `tests/test_compose.sh` y `tests/test_verify.sh` para los comandos de preparación y parsers que hoy pueden fallar sin detener la suite (B030).
- [x] T032 [US3] Sustituir en `tests/test_architecture.sh`, `tests/test_compose.sh`, `tests/test_verify.sh` y `tests/test_verify_stacks.sh` el parsing textual frágil por aserciones estructurales o anclas completas de la configuración (B031).
- [x] T033 [US3] Crear `tests/test_docker_smoke.sh` con el smoke test opt-in del build real de Odoo, sus contextos adicionales y las validaciones efectivas de Nginx, Alloy, Prometheus, Loki y Grafana (B027, B028).
- [x] T034 [US3] Exponer `test-smoke` desde `Makefile` y documentar en `docs/README.md` y `docs/operacion/operar-observability.md` sus requisitos de Docker, red y herramientas, separado de `make test` (B027, B028, B036).
- [x] T035 [TEST][US3] Ejecutar y ajustar `tests/test_addons.sh`, `tests/test_webhook_addons.sh`, `tests/test_build_odoo_image.sh`, `tests/test_image_state.sh` y `tests/test_backup.sh` para que las regresiones cubiertas fallen cuando se rompe cada contrato (B025–B031).

## Fase 5: US4 — Mantener trazabilidad del trabajo de Spec-Flow (P2)

- [x] T036 [US4] Marcar en `.specs/backlog.md` los ítems B001–B041 como completos únicamente después de cerrar su implementación y verificación correspondiente (B038).
- [x] T037 [P][US4] Alinear el estado y las rutas de `.specs/001-gestion-addons-inmutables/spec.md`, `.specs/001-gestion-addons-inmutables/plan.md` y `.specs/001-gestion-addons-inmutables/tasks.md`, identificando el trabajo convergido y el contexto histórico (B037).
- [x] T038 [P][US4] Alinear el estado y las rutas de `.specs/002-edicion-community-enterprise/spec.md`, `.specs/002-edicion-community-enterprise/plan.md` y `.specs/002-edicion-community-enterprise/tasks.md`, identificando el trabajo convergido y el contexto histórico (B037).
- [x] T039 [US4] Homogeneizar idioma, nombres de fases y estructura de `.specs/001-gestion-addons-inmutables/spec.md`, `.specs/001-gestion-addons-inmutables/plan.md`, `.specs/001-gestion-addons-inmutables/tasks.md`, `.specs/002-edicion-community-enterprise/spec.md`, `.specs/002-edicion-community-enterprise/plan.md`, `.specs/002-edicion-community-enterprise/tasks.md`, `.specs/003-correcciones-backlog/spec.md`, `.specs/003-correcciones-backlog/plan.md` y `.specs/003-correcciones-backlog/tasks.md` (B040).
- [x] T040 [P][US4] Corregir en `.make/main.mk` los comentarios que atribuyen a `ARCHITECTURE.md` el agrupamiento de `make help`, dejando la fuente real en Make (B041).
- [x] T041 [TEST][US4] Añadir a `tests/test_architecture.sh` comprobaciones de formato, estado, rutas históricas y presencia versionable de `.specs/backlog.md` (B037–B041).

## Verificación

- [x] VERIFY-001 Ejecutar `make test` y confirmar que todos los tests pasan sin daemon Docker ni red.
- [x] VERIFY-002 Ejecutar `bash -n` sobre los scripts modificados de `scripts/`, `stacks/` y `tests/`.
- [x] VERIFY-003 Ejecutar `docker compose config` para `runtime/desarrollo/compose.yaml`, `runtime/staging/compose.yaml`, `runtime/produccion/compose.yaml` y `runtime/control/compose.yaml`, fusionando los perfiles necesarios para revisar `cert`, `lan` y `restore`.
- [x] VERIFY-004 Ejecutar las verificaciones específicas de host, stacks, edición, addons, backup, integridad y configuración efectiva que correspondan a cada lote.
- [x] VERIFY-005 Ejecutar `make test-smoke` solo en un entorno preparado y registrar por separado el resultado del Docker real.
- [x] VERIFY-006 Confirmar mediante snapshot que `runtime/`, secretos, checkouts privados y estado preexistente permanecen byte a byte sin cambios tras `make test`.
- [x] VERIFY-007 Confirmar que no quedan referencias operativas legacy a `envs/`, `.env` raíz, `addons/addons.txt`, ZIP Enterprise o `state/` raíz, salvo compatibilidad histórica documentada y probada.
- [x] VERIFY-008 Confirmar que `.specs/backlog.md` no conserva ítems abiertos B001–B041 y que todos los archivos creados o modificados están listados en `.specs/003-correcciones-backlog/plan.md`.
- [x] VERIFY-009 Confirmar que no se agregaron dependencias fuera de `.specs/003-correcciones-backlog/plan.md` ni se violó ningún `MUST` de `.specs/constitution.md`.

## Phase 6: Convergence

- [x] T042 Exigir `ENTORNO` y el contexto de `runtime/<entorno>/` en `stacks/backup/scripts/backup.sh`, adaptar `tests/test_backup.sh` al checkout temporal contextualizado y cubrir que no exista fallback operativo a `state/meta` (US2/AC2, B039; contradicts).
- [x] T043 Traducir los encabezados y metadatos de aclaraciones de `.specs/003-correcciones-backlog/spec.md` al español, conservando su estructura uniforme (US4/AC2, T039; partial).
