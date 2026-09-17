# Backlog

Ideas, deferred work, and future features not yet turned into a spec. Ordered by priority — items are removed automatically once `$specify` turns them into a spec.

## P0 — Critical

## P1 — High

## P2 — Medium

- [x] B001 Actualizar README.md y ARCHITECTURE.md para documentar runtime/addons/catalogo.txt como fuente operativa (noted 2026-09-16, from revisión addons)
- [x] B002 Migrar gestionar-fork.md al catálogo y a las rutas actuales de runtime/addons (noted 2026-09-16, from revisión addons)
- [x] B003 Actualizar restore-perdida-total.md para reconstruir addons Community o Enterprise con el flujo vigente (noted 2026-09-16, from revisión addons)
- [x] B004 Reconciliar gestionar-enterprise.md y eliminar las instrucciones obsoletas de instalación por ZIP (noted 2026-09-16, from revisión addons)
- [x] B005 Fortalecer host-verify para validar JSON y comprobar max-size, max-file y log-driver de Docker (noted 2026-09-16, from revisión host)
- [x] B006 Alinear los contratos de host-init y host-verify para que la verificación no dé verde sobre una configuración que la inicialización rechaza (noted 2026-09-16, from revisión host)
- [x] B007 Documentar en configurar-docker-host.md la aplicación de host/daemon.json mediante sudo make host-init (noted 2026-09-16, from revisión host)
- [x] B008 Definir dependencia de red y timeout explícito para las notificaciones SMTP de systemd (noted 2026-09-16, from revisión host)
- [x] B009 Integrar integrity-check.sh al contexto ENTORNO, exponerlo mediante Make y agregarle pruebas (noted 2026-09-16, from revisión scripts)
- [x] B010 Aislar por proyecto y entorno los nombres de contenedores one-off y el lock de operaciones de módulos (noted 2026-09-16, from revisión scripts)
- [x] B011 Exigir ENTORNO en addons-deps y retirar el fallback operativo hacia las rutas antiguas de addons (noted 2026-09-16, from revisión scripts)
- [x] B012 Actualizar vscode-workspace.sh para mostrar runtime/addons y dejar de generar workspaces contra las carpetas antiguas (noted 2026-09-16, from revisión scripts)
- [x] B013 Hacer que pydeps.sh falle ante manifiestos de addons inválidos en lugar de ignorarlos silenciosamente (noted 2026-09-16, from revisión scripts)
- [x] B014 Agregar pruebas para failure-notify.sh y vscode-workspace.sh y ampliar la cobertura de integrity-check.sh (noted 2026-09-16, from revisión scripts)
- [x] B015 Actualizar README.md, PRINCIPLES.md y ARCHITECTURE.md para reflejar runtime/<entorno>/compose.env y eliminar referencias a envs/*.yaml y .env raíz (noted 2026-09-16, from revisión runtime)
- [x] B016 Documentar runtime/control como fragmento exclusivo del runtime productivo y definir sus dependencias de bootstrap (noted 2026-09-16, from revisión runtime)
- [x] B017 Agregar una prueba explícita del límite entre runtime/control incluido en producción y ejecución independiente (noted 2026-09-16, from revisión runtime)
- [x] B018 Documentar qué partes ignoradas de runtime se regeneran y cuáles deben recuperarse desde backup durante una reconstrucción total (noted 2026-09-16, from revisión runtime)
- [x] B019 Reconciliar la retención de Loki entre loki.yaml, el comando Compose y la configuración efectiva del entorno (noted 2026-09-16, from revisión stacks)
- [x] B020 Ejecutar addons-webhook con un usuario no privilegiado y permisos mínimos sobre sus directorios de escritura (noted 2026-09-16, from revisión stacks)
- [x] B021 Documentar y endurecer el límite de privilegios de Alloy por sus montajes de Docker, containerd y del host (noted 2026-09-16, from revisión stacks)
- [x] B022 Agregar validaciones explícitas para stacks bajo perfiles inactivos, especialmente certbot, dnsmasq y backup-restore (noted 2026-09-16, from revisión stacks)
- [x] B023 Actualizar el inventario de stacks en ARCHITECTURE.md para reflejar la cantidad y composición actuales (noted 2026-09-16, from revisión stacks)
- [x] B024 Normalizar los bloques de comentarios de los compose y scripts de stacks al formato obligatorio de dos líneas (noted 2026-09-16, from revisión stacks)
- [x] B025 Hacer herméticos los tests que hoy borran estado ignorado del runtime y preservar cualquier dato operativo existente (noted 2026-09-16, from revisión tests)
- [x] B026 Agregar cobertura directa para el verify de cada stack, no solo para el orquestador y algunos helpers (noted 2026-09-16, from revisión tests)
- [x] B027 Crear un smoke test separado con Docker real para validar el build de la imagen Odoo y sus contextos (noted 2026-09-16, from revisión tests)
- [x] B028 Incorporar validación específica de las configuraciones efectivas de Nginx, Alloy, Prometheus, Loki y Grafana (noted 2026-09-16, from revisión tests)
- [x] B029 Hacer que los stubs de Docker y systemd fallen por defecto cuando falta un fixture esperado (noted 2026-09-16, from revisión tests)
- [x] B030 Agregar aserciones explícitas para los comandos de preparación que hoy pueden fallar sin detener la suite (noted 2026-09-16, from revisión tests)
- [x] B031 Reducir el parsing textual de YAML y salidas operativas en favor de aserciones estructurales más resistentes (noted 2026-09-16, from revisión tests)
- [x] B032 Resolver si addons-webhook pertenece al registro de stacks de Make y, según esa decisión, agregar sus targets o documentar su ciclo de vida exclusivo (noted 2026-09-16, from revisión raíz)
- [x] B033 Corregir la sección repo vacía de make help y asociar repo-sync y repo-status a una agrupación operativa visible (noted 2026-09-16, from revisión raíz)
- [x] B034 Retirar o justificar las reglas legacy de .gitignore para addons/ y state/ frente al modelo operativo bajo runtime/ (noted 2026-09-16, from revisión raíz)
- [x] B035 Retirar CHANGELOG.md del repositorio y documentar que los cambios se registran en cada release (noted 2026-09-16, from revisión raíz)
- [x] B036 Aclarar en Makefile y documentación que make test no requiere daemon Docker ni red, pero sí el cliente Docker Compose (noted 2026-09-16, from revisión raíz)
- [x] B037 Alinear el estado y las rutas documentadas de SPEC-001 y SPEC-002 con la arquitectura convergida o marcarlos explícitamente como históricos (noted 2026-09-16, from revisión docs y specs)
- [x] B038 Incorporar .specs/backlog.md al control de versiones para conservar el backlog entre checkouts y operadores (noted 2026-09-16, from revisión docs y specs)
- [x] B039 Eliminar los residuos de state/ y retirar o aislar el fallback legacy de backup y restore hacia state/meta (noted 2026-09-16, from revisión state)
- [x] B040 Homogeneizar el idioma y los nombres de fases de los artefactos bajo .specs (noted 2026-09-16, from revisión specs)
- [x] B041 Corregir los comentarios de .make que atribuyen el agrupamiento de Make a ARCHITECTURE.md cuando está definido en main.mk (noted 2026-09-16, from revisión .make)

## P3 — Low
