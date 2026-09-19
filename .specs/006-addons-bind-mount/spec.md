# Spec: Addons mediante bind mount

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| addons-bind-mount | SPEC-006 | R01 | 2026-09-18 | Converged |

## Resumen

Ejecutar los addons propios y Enterprise de desarrollo, staging y producción desde `runtime/<entorno>/addons/{custom,enterprise}` mediante bind mounts de solo lectura, conservando la imagen Odoo para el runtime y sus dependencias, para que un cambio exclusivo de código no requiera reconstruirla.

## Métricas de éxito

- Un cambio exclusivo de código de addons puede quedar disponible en cualquiera de los tres entornos sin ejecutar `make build`; se comprueba con una prueba automatizada que falla si el flujo exige construir una imagen.
- La configuración resuelta de los tres entornos monta exactamente `runtime/<entorno>/addons/custom` y, cuando corresponde, `runtime/<entorno>/addons/enterprise` como solo lectura, sin montar el árbol de otro entorno.
- Los cambios de dependencias Python continúan requiriendo una imagen nueva y la suite rechaza operar un módulo cuando la huella de dependencias montada no coincide con la huella registrada por la imagen.
- La verificación identifica si Odoo fue iniciado con commits anteriores a los candidatos publicados y exige recrearlo antes de validar u operar módulos.

## Historias de usuario

### US1 — Iterar addons sin reconstruir Odoo (P1)

Como operador quiero sincronizar código de addons y recrear Odoo sin reconstruir la imagen cuando no cambiaron sus dependencias.

**Escenarios de aceptación**:

- **Dado** un cambio exclusivo de Python, XML o recursos de un addon en la referencia del entorno, **cuando** el operador sincroniza el código y recrea el contenedor Odoo, **entonces** la nueva instancia usa ese código sin ejecutar `make build`.
- **Dado** un addon nuevo cuyas dependencias ya están presentes, **cuando** el operador sincroniza, recrea Odoo e instala el módulo manualmente, **entonces** Odoo descubre el addon desde el bind mount del entorno.

### US2 — Aislar el código de cada entorno (P1)

Como operador quiero que cada runtime consuma únicamente el candidato correspondiente a su rama para impedir cruces entre desarrollo, staging y producción.

**Escenarios de aceptación**:

- **Dado** que desarrollo, staging y producción tienen candidatos diferentes, **cuando** se resuelve la composición de cada runtime, **entonces** cada servicio Odoo monta solo el árbol correspondiente a su `ENTORNO`.
- **Dado** que falta el árbol de addons del entorno, **cuando** se intenta levantar Odoo, **entonces** la operación falla antes de crear el contenedor y explica cómo sincronizarlo.
- **Dado** un contenedor Odoo operativo, **cuando** intenta escribir dentro del árbol de addons, **entonces** el montaje de solo lectura rechaza la escritura.
- **Dado** que staging y producción seleccionan commits Enterprise diferentes durante una validación, **cuando** ambos runtimes conviven, **entonces** cada uno monta su propio `runtime/<entorno>/addons/enterprise` sin modificar el código del otro.
- **Dado** un entorno Community, **cuando** se resuelve y levanta su composición, **entonces** no carga módulos residuales de `runtime/<entorno>/addons/enterprise`.

### US3 — Reconstruir solamente ante cambios de runtime (P1)

Como operador quiero reconstruir la imagen solo cuando cambien Odoo, la edición o las dependencias para conservar un flujo corto sin ocultar incompatibilidades.

**Escenarios de aceptación**:

- **Dado** que cambia un `requirements.txt` o un override de dependencias, **cuando** el operador prepara el entorno, **entonces** el flujo exige resolver dependencias y construir una imagen antes de operar los módulos afectados.
- **Dado** que cambia la versión base de Odoo o la selección Community/Enterprise, **cuando** el operador prepara el entorno, **entonces** el flujo conserva el preflight y la construcción explícita de la imagen.
- **Dado** que solo cambia el commit de addons y su huella de dependencias permanece igual, **cuando** se verifica el runtime, **entonces** la verificación acepta la imagen vigente e informa separadamente la procedencia de la imagen y del código montado.
- **Dado** que la huella de dependencias del código montado difiere de la registrada por `ODOO_IMAGE`, **cuando** se intenta levantar Odoo u operar un módulo, **entonces** la operación falla antes de invocar Compose y pide construir una imagen compatible.

### US4 — Mantener la aplicación bajo control del operador (P1)

Como operador quiero que la automatización de ramas prepare código sin instalar, actualizar ni reiniciar Odoo por sí sola.

**Escenarios de aceptación**:

- **Dado** que el webhook recibe un commit válido, **cuando** publica el candidato del entorno, **entonces** no construye imágenes, reinicia Odoo ni opera módulos.
- **Dado** un candidato actualizado mientras Odoo está activo, **cuando** no hubo una recreación explícita, **entonces** la verificación informa que el runtime conserva una selección anterior y ninguna operación funcional de módulo se ejecuta automáticamente.
- **Dado** que una sincronización intenta publicar código mientras se instala, actualiza o desinstala un módulo, **cuando** ambas acciones concurren, **entonces** el lock compartido las serializa y el árbol no cambia durante la operación funcional.
- **Dado** un cambio que se aplicará en producción, **cuando** el operador inicia el procedimiento, **entonces** el backup y la validación de staging siguen siendo requisitos previos.

## Requisitos no funcionales

- **MUST**: La migración no puede modificar la base ni el filestore durante las pruebas automatizadas.
- **MUST**: La configuración resuelta de Compose debe conservar la separación de identidad, datos, configuración y secretos de los tres entornos.
- **MUST**: La procedencia operativa debe identificar el commit de cada repositorio montado sin requerir un manifiesto mantenido manualmente.
- **MUST**: La imagen debe registrar una huella reproducible de las dependencias instaladas y el runtime debe compararla con la huella derivada de los addons seleccionados antes de levantarse u operar módulos.
- **MUST**: Odoo debe registrar al iniciar los commits de addons que cargó y la verificación debe compararlos con los candidatos publicados del mismo entorno.
- **SHOULD**: El flujo frecuente de cambio exclusivo de código debe requerir como máximo sincronizar, recrear Odoo y operar el módulo cuando corresponda.

## Casos límite

- Si un candidato no contiene un marcador de commit válido o no coincide con el commit exportado desde el clon bare, la verificación falla antes de levantar Odoo u operar el módulo.
- Si dos categorías contienen un módulo con el mismo nombre, se conserva la precedencia vigente del `addons_path`.
- Si se elimina un addon de la rama pero permanece instalado en la base, la verificación informa la divergencia y no intenta desinstalarlo automáticamente.
- Si cambia código mientras Odoo está activo, la automatización no reinicia ni actualiza módulos; el runtime queda marcado como pendiente de recreación hasta que el operador la ejecute.
- Si cambia una dependencia Git, su referencia continúa fijándose a un commit antes de construir la imagen.
- Si una actualización Enterprise debe validarse en staging antes de producción, ambos entornos conservan simultáneamente sus propios commits bajo sus respectivos directorios.

## Supuestos y dependencias

- SPEC-004 continúa definiendo `feat/*`, `19.0-stag` y `19.0` como referencias de desarrollo, staging y producción.
- SPEC-005 continúa definiendo una única imagen Odoo por entorno, pero deja de exigir que esa imagen contenga el código de los addons.
- El catálogo y los clones bare compartidos permanecen bajo `runtime/addons/`; los árboles ejecutables se integran en cada `runtime/<entorno>/addons/{custom,enterprise}`.
- El lock de candidatos y las operaciones manuales de módulos ya existen, pero deben compartir la exclusión del entorno para serializar publicación y operación funcional.

## Fuera de alcance explícito

- Montar addons Enterprise desde un checkout compartido entre entornos, sin tag o con cambios locales.
- Automatizar instalaciones, actualizaciones, desinstalaciones, reinicios o validaciones funcionales de Odoo.
- Eliminar la construcción de la imagen Odoo o instalar dependencias Python directamente en un contenedor activo.
- Agregar una interfaz, un servicio de despliegue o un manifiesto de releases mantenido manualmente.

## Preguntas abiertas
