# Spec: Imagen Odoo única por entorno

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| imagen-odoo-simple | SPEC-005 | R01 | 2026-09-17 | Approved |

## Resumen

Simplificar la operación de Odoo para que cada entorno tenga una única imagen seleccionada y el mismo flujo `build → levantar → verificar`, eliminando la promoción, el rollback y las ranuras `Nueva`, `Actual` y `Anterior`.

## Métricas de éxito

- Los tres entornos operan la imagen Odoo mediante el mismo ciclo explícito: `build → levantar → verificar`.
- El ciclo normal contiene cero operaciones `apply-image`, `rollback-image` o `validate-image`.
- Cada runtime declara exactamente una referencia `ODOO_IMAGE`, explícita y no flotante.
- Ningún script operativo consulta `images.json` ni las ranuras `Nueva`, `Actual` o `Anterior`.

## Historias de usuario

### US1 — Construir una única imagen seleccionada (P1)

Como operador, quiero que la construcción deje una sola referencia de imagen Odoo utilizable por el entorno, para no tener que promover una imagen entre estados antes de levantarla.

**Escenarios de aceptación**:

- **Dado** un entorno con catálogo y dependencias válidos, **cuando** se ejecuta `ENTORNO=<entorno> make build`, **entonces** se construye la imagen Odoo y queda seleccionada como la referencia que Compose utilizará para ese entorno.
- **Dado** un build exitoso, **cuando** se consulta la configuración del entorno, **entonces** existe una única referencia `ODOO_IMAGE` válida y no existen campos o ranuras `Nueva`, `Actual` ni `Anterior` necesarios para levantar Odoo.
- **Dado** un build fallido, **cuando** se consulta la configuración del entorno, **entonces** no se reemplaza silenciosamente la referencia de una imagen funcional por una referencia incompleta.

### US2 — Levantar Odoo sin promoción ni rollback (P1)

Como operador, quiero levantar Odoo directamente después del build, para que el flujo normal no tenga una operación adicional de aplicación de imagen.

**Escenarios de aceptación**:

- **Dado** un build exitoso, **cuando** se ejecuta `ENTORNO=<entorno> make up` o el target del stack Odoo, **entonces** Odoo usa la única referencia seleccionada del entorno.
- **Dado** un entorno configurado, **cuando** se ejecuta el levantamiento, **entonces** no se exige `make apply-image`, una transición de estado ni una imagen anterior.
- **Dado** un entorno sin una `ODOO_IMAGE` construida y seleccionada, o con una referencia bootstrap, flotante o inexistente localmente, **cuando** se ejecuta `make up` u `make odoo-up`, **entonces** la operación falla antes de invocar `docker compose up` para Odoo e indica que debe construirse una imagen válida.

### US3 — Usar el mismo ciclo en los tres entornos (P1)

Como operador, quiero que desarrollo, staging y producción usen el mismo ciclo de imagen, para no mantener tres modelos mentales distintos.

**Escenarios de aceptación**:

- **Dado** cualquiera de los tres entornos, **cuando** se ejecutan sus pasos de código, dependencias, build y levantamiento, **entonces** todos usan la secuencia `build → levantar → verificar`.
- **Dado** que los entornos comparten el daemon Docker, **cuando** cada uno selecciona su imagen, **entonces** las referencias permanecen aisladas por identidad de entorno y no se pisan entre sí.
- **Dado** que un entorno no incluye backup o monitoring, **cuando** se ejecuta su runbook, **entonces** se omiten esos stacks sin introducir estados de imagen alternativos.

### US4 — Levantar el runtime por orden de stacks (P1)

Como operador, quiero que los runbooks indiquen el orden de arranque por stacks, para diagnosticar dependencias y saber qué debe estar disponible antes de cada servicio.

**Escenarios de aceptación**:

- **Dado** cualquiera de los tres entornos, **cuando** se sigue su runbook, **entonces** el orden documentado es Edge, PostgreSQL, Odoo, Backup y Monitoring.
- **Dado** un entorno que no incluye uno de esos stacks, **cuando** se sigue el runbook, **entonces** la etapa se identifica como no aplicable y no se inventa un servicio equivalente.
- **Dado** que Odoo depende de PostgreSQL, **cuando** se sigue el runbook, **entonces** se ejecuta `postgres-verify` después de `postgres-up` y solo se continúa con `odoo-up` si esa verificación termina correctamente.

### US5 — Verificar sin estado de promoción (P1)

Como operador, quiero que `make verify` compruebe la imagen que realmente usa el entorno, para conservar diagnóstico sin mantener una máquina de estados.

**Escenarios de aceptación**:

- **Dado** un entorno levantado, **cuando** se ejecuta `ENTORNO=<entorno> make verify`, **entonces** la verificación informa la referencia Odoo seleccionada y el estado de los stacks incluidos.
- **Dado** un entorno con una referencia Odoo ausente, bootstrap, flotante o inexistente localmente, **cuando** se ejecuta `verify`, **entonces** falla con una causa operativa identificable.
- **Dado** un entorno con operaciones manuales de módulos, **cuando** se ejecuta `verify`, **entonces** no se activa ni bloquea ningún rollback de imagen porque ese mecanismo no existe en este modelo.

## Requisitos no funcionales

- **MUST**: Cada runtime debe mantener una sola referencia operativa `ODOO_IMAGE` para su entorno.
- **MUST**: Las referencias de imagen deben conservar versión y entorno explícitos; no se permite `latest` ni otro tag flotante.
- **MUST**: El flujo no debe requerir `images.json`, las ranuras `Nueva`, `Actual` o `Anterior`, `apply-image` ni `rollback-image` para construir o levantar Odoo.
- **MUST**: El build debe actualizar la referencia seleccionada únicamente después de construir correctamente la imagen.
- **MUST**: La selección de una imagen en desarrollo, staging o producción debe permanecer explícita y separada por `COMPOSE_PROJECT_NAME`.
- **MUST**: Las operaciones de instalación, actualización, desinstalación y validación funcional de módulos deben continuar siendo manuales.
- **SHOULD**: Los tres runbooks deben presentar los mismos nombres y orden de fases, indicando únicamente los stacks que cada entorno no incluye.

## Casos límite

- Si se intenta levantar un entorno recién creado antes de ejecutar un build válido, el procedimiento debe detenerse con una instrucción para construir la imagen.
- Si el build falla después de existir una imagen seleccionada, la referencia anterior debe mantenerse hasta que exista una nueva imagen construida correctamente.
- Si dos entornos usan el mismo daemon Docker, una construcción no debe cambiar el `ODOO_IMAGE` del otro entorno.
- Si quedan tags antiguos en el daemon después de una reconstrucción, no deben formar parte del estado operativo ni aparecer como alternativas de rollback.
- Si staging se restaura desde producción, el restore debe recuperar los datos necesarios sin reintroducir ranuras de imágenes ni una transición automática.
- Si producción necesita una recuperación por backup, el procedimiento debe restaurar el estado de datos y seleccionar una imagen construida explícitamente; no debe depender de rollback de imagen.

## Supuestos y dependencias

- Se mantiene Docker Compose con `include:`, los stacks actuales y la identidad separada por `COMPOSE_PROJECT_NAME`.
- Se mantiene una referencia de imagen no flotante por entorno, aunque cada build pueda generar un tag identificable por momento o contenido.
- Se mantienen los backups de base y filestore y los procedimientos de restore; dejan de asociarse a un mecanismo de rollback de imagen.
- Se mantiene la validación funcional manual en desarrollo y staging antes de promover código hacia producción.
- La implementación requiere revisar la constitución porque su requisito operativo vigente de reversibilidad mediante imagen anterior deja de aplicar.

## No objetivos explícitos

- Mantener una imagen global única compartida entre desarrollo, staging y producción.
- Eliminar las imágenes propias de PostgreSQL, Nginx, backup u observabilidad.
- Automatizar operaciones de módulos, validación funcional, backups o restores.
- Ejecutar limpieza automática de tags antiguos o volúmenes Docker.
- Introducir una nueva interfaz, gestor de imágenes o servicio de despliegue.
- Mantener rollback de imagen como capacidad oculta o alternativa documentada.

## Preguntas abiertas
