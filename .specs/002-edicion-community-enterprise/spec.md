# Spec: Edición Community o Enterprise

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| Edición Community o Enterprise | SPEC-002 | R00 | 2026-09-16 | Approved |

## Resumen

Permitir que cada runtime elija explícitamente Odoo Community o Enterprise mediante
`ODOO_EDITION` y `TAG`, construyendo imágenes trazables y protegiendo las transiciones
de edición que afectan la base de datos.

## Métricas de éxito

N/A: el resultado se mide por los escenarios de aceptación y por la conservación de
los contratos de seguridad, procedencia, backup y reversibilidad del repositorio.

## Historias de usuario

### US1 — Elegir la edición con configuración plana (P1)

Como operador, quiero elegir Community o Enterprise modificando solo la configuración
del runtime, para avanzar con la edición que corresponda sin mantener perfiles ni
archivos de configuración adicionales.

**Escenarios de aceptación**:

- **Dado** un runtime con configuración válida, **cuando** contiene
  `ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`, **entonces** el flujo lo trata
  como Community y no exige checkout, credencial ni tag de Enterprise.
- **Dado** un runtime con configuración válida, **cuando** contiene
  `ODOO_EDITION=enterprise` y `TAG=19.0-ee-YYYY-MM-DD`, **entonces** el flujo lo trata
  como Enterprise y exige la procedencia Enterprise correspondiente.
- **Dado** un runtime, **cuando** la edición y el prefijo de `TAG` no coinciden,
  **entonces** la operación falla antes de construir o promover una imagen.

### US2 — Construir una imagen Community (P1)

Como operador, quiero construir una imagen Community reproducible, para usar Odoo sin
código Enterprise y conservar la misma trazabilidad que en Enterprise.

**Escenarios de aceptación**:

- **Dado** `ODOO_EDITION=community` y candidatos válidos, **cuando** se construye la
  imagen, **entonces** se completa sin checkout ni tag Enterprise y la imagen no
  contiene módulos Enterprise.
- **Dado** una imagen Community construida, **cuando** se publica su procedencia,
  **entonces** registra edición Community, `TAG`, commits de infraestructura y addons,
  digest y momento de construcción.
- **Dado** un checkout Enterprise residual en el runtime, **cuando** se construye una
  imagen Community, **entonces** ese código no se incorpora a la imagen.

### US3 — Construir una imagen Enterprise (P1)

Como operador, quiero conservar el flujo Enterprise existente cuando elijo esa edición,
para no perder el control sobre el código privado ni su procedencia.

**Escenarios de aceptación**:

- **Dado** `ODOO_EDITION=enterprise`, **cuando** falta el checkout o el tag Enterprise,
  **entonces** el build falla antes de modificar `Nueva`.
- **Dado** un tag Enterprise válido, anotado e inmutable, **cuando** se construye la
  imagen, **entonces** la imagen contiene el snapshot seleccionado y registra su tag y
  commit.
- **Dado** un tag Enterprise inválido, liviano, inexistente o distinto del checkout,
  **cuando** se intenta construir, **entonces** la operación falla sin publicar una
  imagen parcial.

### US4 — Promover y revertir sin mezclar ediciones (P1)

Como operador, quiero que el estado de imágenes conozca la edición, para no aplicar una
imagen Community sobre un runtime Enterprise ni ejecutar un rollback incompatible.

**Escenarios de aceptación**:

- **Dado** un runtime con edición configurada, **cuando** `Nueva`, `Actual` o
  `Anterior` no coincide con esa edición, **entonces** `verify`, `apply` y `rollback`
  rechazan la transición e informan la incompatibilidad.
- **Dado** una imagen Community o Enterprise válida, **cuando** se promueve, **entonces**
  `Nueva`, `Actual`, `Anterior`, el selector de Compose y la procedencia conservan la
  misma edición.
- **Dado** una promoción que cambia de edición, **cuando** existe una `Anterior` de la
  edición previa, **entonces** el rollback ordinario no la reactiva automáticamente;
  requiere el procedimiento de transición y su backup asociado.

### US5 — Pasar de Community a Enterprise (P1)

Como operador, quiero incorporar Enterprise a una base Community de forma controlada,
para poder instalar módulos Enterprise sin perder la reversibilidad.

**Escenarios de aceptación**:

- **Dado** una base Community respaldada, **cuando** se prepara una imagen Enterprise y
  se valida en desarrollo y staging, **entonces** producción no se modifica durante
  esas validaciones.
- **Dado** una imagen Enterprise aprobada, **cuando** se aplica en producción,
  **entonces** la base conserva sus módulos Community y la instalación o actualización
  de módulos Enterprise permanece como operación manual posterior.
- **Dado** un fallo durante la transición, **cuando** no hubo operaciones de módulos,
  **entonces** se puede recuperar la imagen anterior y, si hubo operaciones, se debe
  recuperar el backup asociado.

### US6 — Pasar de Enterprise a Community (P1)

Como operador, quiero retirar Enterprise de una base de forma segura, para evitar que
una imagen Community arranque contra módulos Enterprise instalados.

**Escenarios de aceptación**:

- **Dado** una base Enterprise, **cuando** todavía tiene módulos Enterprise instalados,
  **entonces** una transición a Community queda bloqueada.
- **Dado** una copia restaurada de la base sin módulos Enterprise instalados,
  **cuando** se valida una imagen Community en desarrollo y staging, **entonces** la
  imagen puede avanzar sin código Enterprise.
- **Dado** una transición Community aprobada, **cuando** se aplica en producción,
  **entonces** queda registrada la nueva edición y existe un backup asociado para
  recuperar el estado anterior.

### US7 — Restaurar y conservar compatibilidad histórica (P2)

Como operador, quiero que backups y estados existentes sigan siendo interpretables,
para poder recuperar un deployment Enterprise creado antes de esta feature.

**Escenarios de aceptación**:

- **Dado** un estado o backup Enterprise anterior que no tiene el campo de edición,
  **cuando** se lee o restaura, **entonces** se interpreta como Enterprise si conserva
  tag y commit Enterprise válidos.
- **Dado** un backup Community nuevo, **cuando** se restaura, **entonces** conserva la
  edición Community y no intenta recuperar código Enterprise.

## Requisitos no funcionales

- **MUST**: La elección del operador debe requerir únicamente `ODOO_EDITION` y `TAG` en
  el archivo plano de configuración del runtime; no se agregan perfiles ni archivos de
  configuración alternativos.
- **MUST**: El valor de `TAG` debe validarse contra la edición: `19.0-ce-...` para
  Community y `19.0-ee-...` para Enterprise.
- **MUST**: La procedencia de cada imagen debe conservar edición, tag, digest, línea de
  Odoo, commit de infraestructura, commits de addons y momento de construcción.
- **MUST**: Una transición de edición no debe modificar automáticamente módulos,
  registros funcionales ni datos de la base.
- **MUST**: Un cambio de edición debe conservar el backup de base y filestore asociado
  antes de cualquier aplicación en producción.
- **SHOULD**: Los deployments Enterprise existentes deben poder seguir restaurándose
  sin una migración manual de sus metadatos.

## Casos límite

- `ODOO_EDITION` ausente, vacío o distinto de `community` y `enterprise`: la operación
  falla antes de Compose.
- `TAG` ausente, con formato inválido o con prefijo de otra edición: la operación falla
  sin modificar estado.
- Community con un checkout Enterprise residual: el build Community lo ignora y la
  verificación confirma que no fue incorporado.
- Enterprise sin checkout, sin tag anotado o con checkout sucio: el build falla y no
  publica `Nueva`.
- Imagen `Nueva`, `Actual` o `Anterior` de una edición distinta del runtime: se bloquea
  la transición.
- Base Enterprise con módulos Enterprise instalados: se bloquea el cambio a Community
  hasta completar la desinstalación y validación manual sobre una copia.
- Cambio de edición seguido de intento de rollback ordinario: se bloquea si la imagen
  objetivo pertenece a otra edición.
- Estado histórico sin `edition`: se acepta únicamente cuando sus metadatos Enterprise
  permiten identificarlo sin ambigüedad.

## Supuestos y dependencias

- La línea mayor de Odoo continúa definida por el `FROM` pineado del Dockerfile.
- Se conserva el modelo existente de candidatos, imágenes `Nueva`/`Actual`/`Anterior`,
  locks, backups y restores.
- Las operaciones de instalación, actualización y desinstalación de módulos continúan
  siendo manuales.
- Desarrollo y staging siguen siendo los entornos de validación antes de producción.
- La validación de módulos Enterprise instalados depende de la base Odoo restaurada y
  de la operación ORM existente.

## No objetivos explícitos

- Automatizar la conversión funcional de módulos Community a Enterprise o viceversa.
- Permitir cambiar de edición con un simple reinicio de Odoo.
- Descargar automáticamente código Enterprise o credenciales privadas.
- Mantener dos archivos de configuración, perfiles INI o una nueva interfaz para elegir
  la edición.
- Cambiar la política de backups, locks, webhook o aplicación manual de imágenes.

## Preguntas abiertas
