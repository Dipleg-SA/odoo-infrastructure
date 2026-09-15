# Tareas: Gestión de addons inmutables

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| gestion-addons-inmutables | TASKS-001 | R00 | 2026-09-14 | Approved |

## Fase 1: Fundaciones compartidas

- [x] T001 [setup] Crear `runtime/desarrollo/compose.yaml`, `runtime/staging/compose.yaml`, `runtime/produccion/compose.yaml`, `runtime/desarrollo/compose.env.example`, `runtime/staging/compose.env.example` y `runtime/produccion/compose.env.example` con recursos, identidades Compose y rutas aisladas por entorno.
- [x] T002 [P][setup] Actualizar `.gitignore` para ignorar los datos mutables de `runtime/desarrollo/`, `runtime/staging/`, `runtime/produccion/`, `runtime/addons/` y `runtime/control/`, conservando sus plantillas versionadas.
- [x] T003 [setup] Crear `scripts/lib/contexto.sh` para validar `ENTORNO`, cargar `runtime/<entorno>/compose.env` y exponer la invocación centralizada de Compose.
- [x] T004 [P][TEST] Crear `tests/test_contextos.sh` para comprobar entorno obligatorio, valores permitidos, carga aislada y fallo previo a Docker.

## Fase 2: US1 — Operar un entorno explícito (P1)

- [x] T005 [US1] Adaptar `scripts/config-init.sh`, `scripts/secrets-init.sh` y `scripts/secrets-perms.sh` para inicializar únicamente `runtime/<entorno>/config/` y `runtime/<entorno>/secrets/` mediante `scripts/lib/contexto.sh`.
- [x] T006 [P][US1] Adaptar `scripts/verify-host.sh`, `scripts/verify-stacks.sh`, `scripts/timers.sh`, `scripts/odoo-module-operation.sh` y `scripts/odoo-report-config.sh` para requerir `ENTORNO` y usar `scripts/lib/contexto.sh`.
- [x] T007 [P][US1] Adaptar `stacks/nginx/compose.yaml`, `stacks/postgres/compose.yaml`, `stacks/certbot/compose.yaml`, `stacks/cloudflared/compose.yaml` y `stacks/dnsmasq/compose.yaml` para recibir sus rutas desde el runtime seleccionado.
- [x] T008 [P][US1] Adaptar `stacks/prometheus/compose.yaml`, `stacks/loki/compose.yaml`, `stacks/grafana/compose.yaml` y `stacks/alloy/compose.yaml` para recibir sus rutas desde el runtime seleccionado.
- [x] T009 [US1] Actualizar `Makefile` y `.make/layouts.mk` para conservar los verbos operativos bajo el contrato `ENTORNO=<entorno> make <verbo>`.
- [x] T010 [US1] Retirar `.env.development.example`, `.env.staging.example`, `.env.production.example`, `envs/development.yaml`, `envs/staging.yaml` y `envs/production.yaml` después de migrar sus contratos a `runtime/`.
- [x] T011 [TEST][US1] Actualizar `tests/test_compose.sh`, `tests/test_scripts.sh` y `tests/test_verify.sh` para resolver los tres runtimes, comprobar recursos no superpuestos y rechazar el selector raíz anterior.

## Fase 3: US2 — Recibir código candidato por entorno (P1)

- [x] T012 [US2] Crear `runtime/addons/catalogo.txt.example` y adaptar `scripts/addons.sh` para leer el catálogo de dominios, mantener clones bare en `runtime/addons/.repos/` y materializar candidatos bajo `runtime/addons/custom/<entorno>/`.
- [x] T013 [P][US2] Crear `runtime/control/compose.yaml` y `stacks/addons-webhook/compose.yaml`, e incluir el receptor solo en `runtime/produccion/compose.yaml` mediante la red edge y los recursos mínimos `runtime/control/`, `runtime/addons/.repos/` y `runtime/addons/custom/`.
- [x] T014 [P][US2] Crear `stacks/addons-webhook/image/Dockerfile` con una imagen Python de referencia explícita para el receptor.
- [x] T015 [US2] Crear `scripts/lib/candidate-lock.sh` y `stacks/addons-webhook/app/server.py` para validar HMAC, filtrar repositorios y ramas del catálogo, tomar el lock por entorno y publicar cada commit candidato de forma atómica.
- [x] T016 [P][US2] Adaptar `stacks/nginx/compose.yaml`, `stacks/nginx/config/server-tls.conf` y `stacks/nginx/config/server-plain.conf`, y crear `stacks/nginx/config/addons-webhook.locations` para publicar solo la ruta del receptor hacia la red edge.
- [x] T017 [P][US2] Crear `stacks/addons-webhook/verify.sh` para afirmar que el receptor no recibe Docker, Odoo, Postgres, filestore, Enterprise, secretos de Odoo ni referencias de imagen.
- [x] T018 [TEST][US2] Actualizar `tests/test_addons.sh`, `tests/test_compose.sh` y crear `tests/test_webhook_addons.sh` para cubrir ruta pública, ramas por entorno, allowlist, HMAC, idempotencia, serialización y ausencia de cambios sobre Odoo activo.

## Fase 4: US5 — Mantener Enterprise sin variantes de entorno (P2)

- [x] T019 [US5] Extender `scripts/addons.sh` para administrar `runtime/addons/enterprise/` fuera del catálogo y exigir un tag inmutable de la línea mayor antes de fotografiarlo.
- [x] T020 [TEST][US5] Actualizar `tests/test_addons.sh` y `tests/test_webhook_addons.sh` para verificar que Enterprise no es un candidato, no recibe webhooks y falla si su tag no se resuelve de forma inmutable.

## Fase 5: US3 — Construir una imagen inmutable trazable (P1)

- [x] T021 [US3] Crear `scripts/image-state.sh` para leer y escribir `runtime/<entorno>/state/images.json` con Nueva, Actual, Anterior, validación y procedencia completa.
- [x] T022 [US3] Crear `scripts/build-odoo-image.sh` para tomar `scripts/lib/candidate-lock.sh`, exportar los commits de candidato desde clones bare a `runtime/addons/builds/<entorno>/<identificador>/`, derivar el tag inmutable y registrar Nueva solo al finalizar build y digest.
- [x] T023 [P][US3] Adaptar `scripts/pydeps.sh` para derivar e instalar dependencias desde los manifiestos de Enterprise y de todos los dominios de una fotografía.
- [x] T024 [US3] Adaptar `stacks/odoo/compose.yaml` para consumir `ODOO_IMAGE` y eliminar cualquier bind mount de addons del host.
- [x] T025 [US3] Adaptar `stacks/odoo/image/Dockerfile` para copiar la fotografía a `/opt/odoo/enterprise/` y `/opt/odoo/custom/` fuera de `/mnt/extra-addons`.
- [x] T026 [US3] Adaptar `stacks/odoo/image/entrypoint.sh` para construir `addons_path` con Enterprise primero, luego los dominios propios y finalmente Community.
- [x] T027 [US3] Adaptar `stacks/odoo/verify.sh` para informar imagen Actual, digest y procedencia, y rechazar addons montados desde el host.
- [x] T028 [TEST][US3] Crear `tests/test_build_odoo_image.sh` y `tests/test_image_state.sh` para verificar fotografía desde SHAs inmutables, exclusión frente al webhook, build atómico, tag/digest/procedencia, dependencias y rutas internas de addons.
- [x] T029 [TEST][US3] Actualizar `tests/test_compose.sh` para detectar bind mounts de addons, referencias a `/mnt/extra-addons` y uso de una imagen Odoo sin identidad explícita.

## Fase 6: US4 — Promover y revertir versiones de forma controlada (P1)

- [ ] T030 [US4] Extender `scripts/image-state.sh` con las transiciones Nueva a Actual, Actual a Anterior, reactivación de Anterior y registro de validación.
- [ ] T031 [US4] Actualizar `Makefile` y `.make/layouts.mk` para exponer `build`, `apply-image`, `rollback-image` y `validate-image` bajo el entorno explícito, sin automatizar operaciones de módulos.
- [ ] T032 [US4] Adaptar `scripts/odoo-module-operation.sh` para exigir una imagen Actual y registrar si la operación invalida el rollback solo de imagen.
- [ ] T033 [US4] Adaptar `stacks/backup/compose.yaml`, `stacks/backup/scripts/backup.sh`, `stacks/backup/scripts/restore.sh` y `stacks/backup/verify.sh` para guardar y restaurar junto al snapshot la procedencia de Actual y Anterior.
- [ ] T034 [US4] Adaptar `stacks/odoo/compose.yaml` y `stacks/odoo/verify.sh` para que aplicar o revertir use exclusivamente la referencia Actual declarada en `runtime/<entorno>/state/images.json`.
- [ ] T035 [TEST][US4] Actualizar `tests/test_backup.sh` y `tests/test_scripts.sh` para cubrir backup previo en producción, restauración con imagen declarada y bloqueo del rollback de imagen tras operaciones de módulos.
- [ ] T036 [TEST][US4] Actualizar `tests/test_image_state.sh` para cubrir transiciones, conservación de Anterior y promoción serializada con el mismo tag y commit Enterprise.

## Fase 7: Integración y verificación

- [ ] T037 [integration] Actualizar `docs/modulos/especificacion-gestion-addons.md` para reflejar los contratos implementados y mantener la estructura objetivo como fuente de operación.
- [ ] T038 [integration] Actualizar `docs/entorno/levantar-desarrollo.md`, `docs/entorno/levantar-staging.md`, `docs/entorno/levantar-produccion.md`, `docs/backup-restore/restore-staging.md`, `docs/modulos/gestionar-modulo.md`, `docs/operacion/operar-odoo.md` y `docs/operacion/operar-backups.md` con el entorno explícito, el descarte/resembrado y la operación manual de módulos.
- [ ] T039 [integration] Crear `docs/modulos/gestionar-catalogo-addons.md`, `docs/modulos/construir-y-aplicar-imagen.md`, `docs/modulos/validar-promocion.md`, `docs/operacion/operar-webhook-addons.md` y `docs/credenciales/configurar-webhook-github.md`, incluyendo la limpieza manual antes de retirar un repositorio del catálogo.
- [ ] T040 [integration] Ejecutar `make test`, `bash -n` sobre scripts modificados y `docker compose config` para `runtime/control/compose.yaml` y cada `runtime/<entorno>/compose.yaml`, corrigiendo cualquier contrato incumplido.

## Verificación

- [ ] VERIFY Todos los escenarios de aceptación de `spec.md` pasan.
- [ ] VERIFY Se cumplen los requisitos no funcionales de `spec.md`: aislamiento del receptor, build atómico, metadatos de backup y detección del modelo anterior.
- [ ] VERIFY Ningún principio MUST pertinente de `.specs/constitution.md` es vulnerado.
- [ ] VERIFY No se crean archivos fuera de la estructura declarada en `plan.md`.
- [ ] VERIFY No se agregan dependencias fuera de Compose, Git, Docker y la biblioteca estándar de Python declaradas en `plan.md`.
