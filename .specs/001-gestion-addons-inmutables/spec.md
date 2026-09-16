# Spec: Gestión de addons inmutables

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| gestion-addons-inmutables | SPEC-001 | R00 | 2026-09-15 | Converged |

## Resumen

La infraestructura debe permitir que desarrollo, staging y producción compartan un checkout por línea mayor de Odoo, sin compartir código activo, secretos, configuración ni estado operativo, y deben ejecutar solamente imágenes inmutables que incorporen Enterprise y los addons propios correspondientes.

## Métricas de éxito

- Aislamiento de entornos: las tres composiciones resuelven desde el mismo checkout y cada una referencia únicamente sus propios secretos, configuración, estado, volúmenes e identidad Compose.
- Trazabilidad de imagen: el 100% de las imágenes Nueva, Actual y Anterior registra línea mayor, imagen base, commit de infraestructura, tag y commit Enterprise, y commits de addons de dominio.
- Actualización no disruptiva: un evento Git válido no cambia contenedores, imágenes activas ni bases de datos.

## Historias de usuario

### US1 — Operar un entorno explícito (P1)

Como operador, quiero seleccionar desarrollo, staging o producción de forma explícita para ejecutar los verbos existentes sin que el entorno dependa de un `.env` raíz compartido.

**Escenarios de aceptación**:

- **Dado** un checkout con los tres runtimes configurados, **cuando** se ejecuta una operación para staging, **entonces** Compose usa solo la composición, los secretos, la configuración y el estado de staging.
- **Dado** una operación sin entorno seleccionado, **cuando** intenta afectar Odoo, Postgres, backups o módulos, **entonces** falla antes de invocar Docker Compose.
- **Dado** desarrollo, staging y producción activos, **cuando** se inspeccionan sus recursos de Compose, **entonces** sus proyectos, volúmenes, redes y contenedores no se superponen.

### US2 — Recibir código candidato por entorno (P1)

Como operador, quiero que los cambios publicados en las ramas de integración actualicen únicamente el candidato del entorno asociado, para revisar y construir código nuevo sin alterar Odoo en ejecución.

**Escenarios de aceptación**:

- **Dado** un push válido a `19.0-dev`, **cuando** el receptor lo procesa, **entonces** solo cambia el candidato de desarrollo de ese repositorio de dominio.
- **Dado** un push repetido o reintentado, **cuando** el receptor lo procesa, **entonces** el candidato termina en el mismo commit y no se crea una reconciliación concurrente.
- **Dado** un push a una rama `feat/*` o a un repositorio ausente del catálogo, **cuando** el receptor lo procesa, **entonces** no cambia ningún candidato.
- **Dado** un candidato actualizado, **cuando** se consulta Odoo, **entonces** sigue ejecutando la imagen Actual previa.

### US3 — Construir una imagen inmutable trazable (P1)

Como operador, quiero construir una imagen desde una fotografía estable de Enterprise y de los candidatos de dominio para aplicar una versión conocida manualmente.

**Escenarios de aceptación**:

- **Dado** un tag Enterprise seleccionado y candidatos de un entorno, **cuando** se inicia un build, **entonces** la imagen contiene Enterprise antes de los addons propios y no monta código desde el host.
- **Dado** una fotografía de build, **cuando** se resuelven dependencias Python, **entonces** se consideran los manifiestos de Enterprise y de todos los dominios incluidos.
- **Dado** un build exitoso, **cuando** se registra Nueva, **entonces** recibe un tag único con línea, entorno, momento UTC y hash de la fotografía, además de su digest y procedencia completa.
- **Dado** un webhook recibido durante el build, **cuando** termina el build, **entonces** la imagen conserva la fotografía inicial y el webhook queda disponible solo para el build siguiente.

### US4 — Promover y revertir versiones de forma controlada (P1)

Como operador, quiero aplicar una imagen solo después de validar el entorno anterior y poder volver a un estado consistente si la validación falla.

**Escenarios de aceptación**:

- **Dado** una Nueva validable, **cuando** se aplica a un entorno, **entonces** Nueva pasa a Actual y la Actual previa pasa a Anterior.
- **Dado** una validación fallida sin operaciones de módulos, **cuando** el operador decide volver atrás, **entonces** se reactiva Anterior sin restaurar la base.
- **Dado** una validación de producción con operaciones de módulos, **cuando** falla, **entonces** se restaura el backup creado antes de aplicar y la imagen indicada por sus metadatos.
- **Dado** una promoción de una versión, **cuando** avanza por desarrollo, staging y producción, **entonces** las tres imágenes usan el mismo tag Enterprise inmutable y los dominios de la rama correspondiente.

### US5 — Mantener Enterprise sin variantes de entorno (P2)

Como operador, quiero usar un único repositorio privado Enterprise por línea mayor y seleccionar una revisión mediante tags inmutables, sin crear ramas Enterprise por entorno ni automatizar su aplicación.

**Escenarios de aceptación**:

- **Dado** un commit autorizado de Enterprise `19.0`, **cuando** se habilita para una promoción, **entonces** se crea un tag inmutable que lo identifica.
- **Dado** una promoción serializada, **cuando** se construyen sus imágenes por entorno, **entonces** todas usan el mismo tag y commit Enterprise.
- **Dado** un evento GitHub del repositorio Enterprise, **cuando** llega al receptor, **entonces** se ignora y no altera candidatos ni imágenes.

## Requisitos no funcionales

- **MUST**: El receptor de webhooks no puede acceder al socket Docker, bases de datos, filestore, secretos de Odoo, credenciales de Enterprise ni referencias de imagen.
- **MUST**: Los builds deben fallar antes de crear Nueva si falta una fuente fotografiada o una dependencia Python no se puede resolver e instalar.
- **MUST**: Los metadatos de backup deben incluir Actual, Anterior y la procedencia completa de ambas imágenes.
- **SHOULD**: Las verificaciones estáticas deben detectar referencias al modelo anterior de `.env` raíz, `ADDONS_BRANCH` en servidor y bind mounts de addons.

## Casos límite

- Si un repositorio se retira del catálogo, sus módulos se desinstalan y limpian manualmente antes de eliminar su código de las imágenes futuras.
- Si el tag Enterprise seleccionado no existe o no apunta al commit esperado, el build falla sin modificar Nueva, Actual ni Anterior.
- Si desarrollo o staging requirieron operaciones de módulos durante una validación fallida, se descartan y recrean; staging se siembra nuevamente desde el último backup válido de producción.
- Si comienza una migración de línea mayor, la línea objetivo usa un checkout y runtime independientes, incluido su checkout Enterprise para la línea objetivo.

## Supuestos y dependencias

- La organización de GitHub puede entregar eventos `push` de repositorios de dominio al receptor del checkout canónico.
- El repositorio Enterprise privado se actualiza de forma autorizada y el operador selecciona sus tags antes de iniciar una promoción.
- El host dispone de Docker Compose compatible con `include:` y de acceso de solo lectura a los repositorios requeridos.

## No objetivos explícitos

- Instalar, actualizar, desinstalar o validar funcionalmente módulos de Odoo de forma automática.
- Reemplazar la revisión manual de pull requests entre ramas de integración.
- Crear una UI, dashboard o sistema de notificaciones para candidatos, imágenes o webhooks.
- Convertir el checkout local de una feature en un cuarto entorno del servidor.

## Preguntas abiertas
