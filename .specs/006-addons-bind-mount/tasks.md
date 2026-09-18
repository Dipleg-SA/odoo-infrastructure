# Tasks: Addons mediante bind mount

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| addons-bind-mount | TASKS-006 | R00 | 2026-09-18 | Approved |

## Fase 1: Preparación

- [x] T001 [setup] Confirmar la rama `006-addons-bind-mount`, el estado del árbol y la configuración resuelta actual de `stacks/odoo/compose.yaml` para conservar una referencia previa a los cambios.

## Fase 2: US2 — Aislar el código de cada entorno (P1)

- [x] T002 [US2] Declarar `RUNTIME_ADDONS_DIR` con una ruta propia en `runtime/desarrollo/compose.env.example`, `runtime/staging/compose.env.example` y `runtime/produccion/compose.env.example`.
- [x] T003 [P][TEST][US2] Extender `tests/test_contextos.sh` para exigir rutas de addons distintas y coherentes con cada entorno.
- [x] T004 [US2] Adaptar `scripts/addons.sh` para publicar custom en `runtime/<entorno>/addons/custom` y sincronizar Enterprise en `runtime/<entorno>/addons/enterprise`.
- [x] T005 [US2] Generar y validar `.candidate-tree` en `scripts/addons.sh` con semántica de árbol Git, excluyendo ambos marcadores e incluyendo rutas, contenido, bit ejecutable y enlaces simbólicos.
- [x] T006 [TEST][US2] Actualizar `tests/test_addons.sh` para cubrir destinos por entorno, marcadores, mutaciones de contenido, permisos ejecutables, enlaces simbólicos y checkouts Enterprise independientes.
- [x] T007 [US2] Montar custom y Enterprise desde `RUNTIME_ADDONS_DIR` como solo lectura y pasar `ODOO_EDITION` en `stacks/odoo/compose.yaml`.
- [x] T008 [TEST][US2] Actualizar `tests/test_compose.sh` para comprobar los mounts resueltos de desarrollo, staging y producción, su modo de solo lectura y la ausencia de cruces.
- [x] T009 [US2] Aplicar en `stacks/odoo/image/entrypoint.sh` el gate de edición para excluir Enterprise en Community y conservar la precedencia vigente del `addons_path`.
- [x] T010 [P][TEST][US2] Extender `tests/test_edition_transition.sh` para cubrir checkouts Enterprise por entorno y residuos ignorados al cambiar a Community.
- [x] T011 [P][TEST][US2] Extender `tests/test_docker_smoke.sh` para comprobar el mount efectivo, el descubrimiento de addons y el rechazo de escritura dentro del contenedor.
- [x] T012 [US2] Separar en `stacks/addons-webhook/compose.yaml` los mounts escribibles de custom para desarrollo, staging y producción sin exponer Enterprise.
- [x] T013 [US2] Adaptar `stacks/addons-webhook/app/server.py` para resolver el destino del entorno y publicar atómicamente solo dentro de su árbol custom.
- [x] T014 [TEST][US2] Actualizar `tests/test_webhook_addons.sh` para cubrir los tres destinos, impedir cruces y verificar que Enterprise queda fuera del webhook.
- [x] T015 [US2] Crear en `scripts/addons-runtime.sh` la inicialización idempotente de los tres custom con propietario operador, grupo `65532` y modo `2775`, más un diagnóstico con el comando privilegiado exacto cuando no pueda aplicarlo.
- [x] T016 [US2] Agregar `addons-runtime-init` y el preflight previo a `addons-webhook-up` en `Makefile` para impedir que Compose cree directorios ausentes como root.
- [x] T017 [TEST][US2] Extender `tests/test_scripts.sh` y `tests/test_webhook_addons.sh` para cubrir creación, idempotencia, permisos incompatibles y fallo anterior a Compose.
- [x] T018 [US2] Actualizar `stacks/addons-webhook/verify.sh` para validar exactamente los tres destinos custom escribibles, sus permisos esperados y la ausencia de mounts Enterprise.
- [x] T019 [TEST][US2] Cubrir en `tests/test_webhook_addons.sh` que la verificación propia del stack falla si falta un destino, aparece Enterprise o cambia la superficie de escritura.

## Fase 3: US3 — Reconstruir solamente ante cambios de runtime (P1)

- [x] T020 [US3] Hacer que `scripts/pydeps.sh` compile `runtime/<entorno>/addons/requirements.lock.txt` y calcule huellas canónicas de entradas y lock por entorno.
- [x] T021 [TEST][US3] Extender `tests/test_pydeps.sh` para distinguir cambios de código sin efecto en dependencias de cambios en `requirements.txt`, overrides o `external_dependencies.python`.
- [x] T022 [US3] Extender `scripts/addons-runtime.sh` con validación, inventario y comparación de `odoo_base` y huellas de dependencias entre el entorno y la imagen.
- [x] T023 [US3] Retirar la copia de custom y Enterprise de `stacks/odoo/image/Dockerfile`, conservando la base Odoo, wheels, dependencias y entrypoint.
- [x] T024 [US3] Adaptar `scripts/build-odoo-image.sh` para resolver dependencias desde una fotografía estable y registrar `odoo_base`, `requirements_inputs_sha256` y `requirements_lock_sha256` en `image.json` sin presentar addons como contenido de la imagen.
- [x] T025 [TEST][US3] Actualizar `tests/test_build_odoo_image.sh` para exigir una imagen sin código de addons, una fotografía estable y metadata reproducible que cambie al modificar la referencia base de Odoo o sus dependencias.
- [x] T026 [US3] Adaptar `scripts/odoo-edition-check.sh` para validar la selección Enterprise del runtime del entorno y exigir una construcción explícita ante cambios de edición.
- [x] T027 [TEST][US3] Completar `tests/test_edition_transition.sh` con los casos de preflight y rebuild requeridos al cambiar entre Community y Enterprise.
- [x] T028 [US3] Ajustar las variables, guardas de build y rutas de dependencias por entorno en `Makefile`.

## Fase 4: US1 — Iterar addons sin reconstruir Odoo (P1)

- [x] T029 [US1] Unificar en `scripts/lib/candidate-lock.sh` la ruta y adquisición del lock por entorno que compartirán sincronización, webhook, lifecycle, build y operaciones de módulos.
- [x] T030 [US1] Crear `scripts/odoo-lifecycle.sh` para ejecutar el preflight y recrear Odoo mediante `up -d --force-recreate` bajo el lock compartido, sin usar `docker compose restart` ni invocar build por cambios exclusivos de código.
- [x] T031 [US1] Enrutar los targets Odoo de `.make/layouts.mk` por `scripts/odoo-lifecycle.sh` y conservar separados los demás stacks.
- [x] T032 [US1] Adaptar `scripts/odoo-module-operation.sh` para validar integridad, `odoo_base` y dependencias bajo el lock compartido antes de detener Odoo y ejecutar la operación manual.
- [x] T033 [TEST][US1] Actualizar `tests/test_addon_operations.sh` para cubrir preflight, versión base incompatible, exclusión mutua, recreación y operaciones install/update/uninstall sin build implícito.
- [x] T034 [TEST][US1] Extender `tests/test_scripts.sh` para comprobar `up -d --force-recreate`, el uso del lock, el rechazo anterior a Compose y la ausencia de reinicios o builds fuera de una acción explícita.
- [x] T035 [US1] Adaptar `scripts/vscode-workspace.sh` para exponer custom y Enterprise del entorno seleccionado sin referenciar árboles compartidos obsoletos.
- [x] T036 [US1] Actualizar en `Makefile` la limpieza acotada y los targets de sincronización, dependencias, lifecycle y módulos para las rutas `runtime/<entorno>/addons`.

## Fase 5: US4 — Mantener la aplicación bajo control del operador (P1)

- [x] T037 [US4] Registrar en `/tmp/odoo-addons-startup.json` desde `stacks/odoo/image/entrypoint.sh` el entorno, edición, commits y huellas que Odoo encontró antes de arrancar.
- [x] T038 [US4] Adaptar `stacks/odoo/verify.sh` para validar mounts, integridad, `odoo_base`, huellas y diferencias entre la selección de arranque y los candidatos actuales con mensajes accionables.
- [x] T039 [TEST][US4] Actualizar `tests/test_verify.sh` para cubrir runtime al día, candidato posterior al arranque, árbol alterado, base o dependencia incompatible y addon instalado ausente sin automatizar su desinstalación.
- [x] T040 [US4] Hacer que `stacks/backup/scripts/backup.sh` registre la selección cargada desde el contenedor Odoo y conserve compatibilidad diagnóstica con metadata histórica.
- [x] T041 [US4] Adaptar `stacks/backup/verify.sh` para exigir procedencia ejecutada en snapshots nuevos sin tratar metadata antigua como selección aplicable.
- [x] T042 [TEST][US4] Actualizar `tests/test_backup.sh` para comprobar que el snapshot usa los commits de inicio y no el candidato publicado después.
- [x] T043 [US4] Adaptar `scripts/promotion-verify.sh` para comparar los candidatos productivos con custom y Enterprise efectivamente cargados por staging y fallar si staging no está operativo.
- [x] T044 [TEST][US4] Actualizar `tests/test_promotion_verify.sh` para cubrir selección cargada, candidato más nuevo no probado, Enterprise independiente y staging detenido.
- [x] T045 [TEST][US4] Completar `tests/test_webhook_addons.sh` para demostrar que el webhook no construye imágenes, recrea Odoo ni instala, actualiza o desinstala módulos.
- [x] T046 [US4] Alinear `stacks/addons-webhook/app/server.py` con `scripts/lib/candidate-lock.sh` para serializar publicaciones y operaciones funcionales con el mismo lock por entorno y repositorio.
- [x] T047 [TEST][US4] Extender `tests/test_webhook_addons.sh` y `tests/test_addon_operations.sh` con una contención concurrente que impida cambiar el árbol durante una operación de módulo.

## Fase 6: Contratos y procedimientos

- [x] T048 [P][US1][US3] Actualizar `PRINCIPLES.md` y `ARCHITECTURE.md` con la separación entre imagen, dependencias, candidatos montados, recreación y selección cargada al arranque.
- [x] T049 [TEST][US1][US3] Actualizar `tests/test_architecture.sh` para exigir los cuatro contratos y rechazar documentación que vuelva a describir addons embebidos o `docker compose restart` para aplicar candidatos.
- [x] T050 [P][US1][US2] Actualizar `docs/entorno/levantar-desarrollo.md`, `docs/entorno/levantar-staging.md` y `docs/entorno/levantar-produccion.md` con las rutas, ramas y secuencia explícita de cada entorno.
- [x] T051 [P][US1][US3] Actualizar `docs/modulos/construir-y-aplicar-imagen.md`, `docs/modulos/gestionar-dependencias-python.md` y `docs/modulos/gestionar-modulo.md` con `odoo_base`, el criterio de rebuild, el preflight y la recreación explícita.
- [x] T052 [P][US2][US4] Actualizar `docs/modulos/especificacion-gestion-addons.md`, `docs/modulos/gestionar-catalogo-addons.md` y `docs/modulos/gestionar-fork.md` con destinos por entorno, bootstrap y publicación sin acciones funcionales.
- [x] T053 [P][US2][US4] Actualizar `docs/modulos/gestionar-enterprise.md`, `docs/modulos/gestionar-ramas-staging.md` y `docs/modulos/validar-promocion.md` con checkouts separados y comparación contra staging ejecutado.
- [x] T054 [P][US4] Actualizar `docs/backup-restore/realizar-backup.md`, `docs/backup-restore/restore-staging.md`, `docs/backup-restore/restore-perdida-total.md` y `docs/backup-restore/migrar-deployment-externo.md` con procedencia ejecutada y reconstrucción de mounts por entorno.
- [x] T055 [P][US1][US4] Actualizar `docs/operacion/operar-odoo.md`, `docs/operacion/operar-webhook-addons.md` y `docs/operacion/operar-backups.md` con recreación explícita, candidato pendiente y metadata de backup.

## Verificación

- [x] VERIFY Ejecutar `bash -n` sobre `scripts/addons-runtime.sh`, `scripts/addons.sh`, `scripts/build-odoo-image.sh`, `scripts/lib/candidate-lock.sh`, `scripts/odoo-edition-check.sh`, `scripts/odoo-lifecycle.sh`, `scripts/odoo-module-operation.sh`, `scripts/promotion-verify.sh`, `scripts/pydeps.sh`, `scripts/vscode-workspace.sh`, `stacks/addons-webhook/verify.sh`, `stacks/backup/scripts/backup.sh`, `stacks/backup/verify.sh`, `stacks/odoo/image/entrypoint.sh` y `stacks/odoo/verify.sh`.
- [x] VERIFY Ejecutar `make test` y confirmar que las pruebas de contratos, scripts, Compose, webhook, backup, build, dependencias y promoción pasan sin Docker levantado ni red.
- [x] VERIFY Resolver `docker compose config` para desarrollo, staging y producción y comprobar que cada Odoo monta únicamente `runtime/<entorno>/addons/{custom,enterprise}` en modo de solo lectura.
- [x] VERIFY Ejecutar `tests/test_docker_smoke.sh` cuando haya daemon disponible y confirmar descubrimiento de addons, rechazo de escritura y exclusión Enterprise en Community sin tocar base ni filestore operativos.
- [x] VERIFY Recorrer todos los escenarios de aceptación de `.specs/006-addons-bind-mount/spec.md`: código sin build, aislamiento, rebuild por versión base, dependencias o edición, drift tras sincronización y automatización limitada a candidatos.
- [x] VERIFY Confirmar todos los requisitos no funcionales de `.specs/006-addons-bind-mount/spec.md`, en especial procedencia automática, huellas reproducibles, separación de entornos y ausencia de cambios sobre base o filestore.
- [x] VERIFY Confirmar que `stacks/addons-webhook/verify.sh`, `stacks/backup/verify.sh` y `stacks/odoo/verify.sh` conservan dentro de cada stack sus expectativas desplegadas y que `make verify` solo las orquesta.
- [x] VERIFY Confirmar que ningún principio MUST de `.specs/constitution.md` fue vulnerado, incluidos operación manual, separación real, Compose verificable, procedencia y ausencia de dependencias o servicios nuevos.
- [x] VERIFY Confirmar que no se creó ningún archivo de implementación fuera de la estructura declarada en `.specs/006-addons-bind-mount/plan.md` y que no se agregó ninguna dependencia nueva.
