# Constitución del proyecto

| Nombre | Versión | Fecha | Estado |
| --- | --- | --- | --- |
| odoo-infrastructure | R00 | 2026-09-14 | Approved |

## Propósito

Este repositorio provee infraestructura Docker autoalojada para una instancia de Odoo operada por una persona en un único servidor. Versiona los stacks, su composición y sus procedimientos; los valores y secretos propios de cada deployment viven fuera del control de versiones.

## Stack tecnológico

- **Lenguaje**: Bash, Make y YAML de Docker Compose.
- **Runtime y framework**: Docker Engine y Docker Compose con `include:`.
- **Base de datos**: PostgreSQL para Odoo, ejecutado en su stack propio.
- **Pruebas**: scripts Bash bajo `tests/`, ejecutados con `make test` sin Docker levantado ni red.
- **Formato y validación**: `bash -n`, `docker compose config` y las verificaciones de cada stack.

## Principios de código

- **MUST**: Mantener scripts, comentarios, documentación y salida para el operador en español.
- **MUST**: Mantener un stack por contenedor, con imagen, configuración, scripts, unidades y verificación en su propia carpeta.
- **MUST**: Mantener los cambios de Compose verificables con `docker compose config`; los scripts modificados deben tener pruebas que fallen al romper el contrato cubierto.
- **MUST**: Evitar dependencias y servicios nuevos cuando Docker, Postgres, nginx o un componente existente cubran la necesidad.
- **SHOULD**: Preferir cambios pequeños y responsabilidades acotadas, conservando los verbos operativos existentes cuando expresen el contrato necesario.

## Seguridad

- **MUST**: Gestionar secretos mediante `secrets:` de Compose como archivos con permisos y grupos compatibles con sus consumidores; nunca por variables de entorno.
- **MUST**: Definir exposición por `ports:` y segmentación por redes; ningún servicio puede publicarse en `0.0.0.0`.
- **MUST**: Restringir toda credencial al privilegio mínimo y no exponer el socket Docker a servicios que reciban tráfico o comandos del operador.
- **MUST**: Mantener Enterprise, los secretos de deployment y los artefactos privados fuera del repositorio público de infraestructura.
- **SHOULD**: Ejecutar contenedores como usuarios no root cuando la imagen base lo permita.

## Principios operativos

- **MUST**: Conservar base de datos y filestore en el mismo snapshot de backup.
- **MUST**: Mantener la aplicación de imágenes y las operaciones de módulos como decisiones explícitas del operador.
- **MUST**: Preservar la reversibilidad: sin operaciones de módulos se puede reactivar la imagen anterior; con operaciones de módulos se restaura el backup asociado.
- **MUST**: Mantener desarrollo y staging descartables y validar los cambios riesgosos antes de producción.
- **MUST**: Mantener la separación real de secretos, configuraciones, volúmenes, estado e identidad Compose entre entornos que convivan en un checkout.
- **SHOULD**: Mantener procedimientos simples de ejecutar y de diagnosticar para una sola persona operadora.

## Observabilidad

- **MUST**: Conservar métricas de host, contenedores, base de datos y aplicación, además de logs centralizados y alertas efectivas.
- **MUST**: Mantener retención explícita y acotada para métricas y logs.
- **MUST**: Hacer que cada stack conserve su propia verificación y que `make verify` las orqueste sin duplicar expectativas.
- **SHOULD**: Registrar la procedencia completa de una imagen y asociarla a los metadatos de backup para facilitar diagnóstico y restauración.

## Rendimiento

- **MUST**: Mantener límites de recursos explícitos por contenedor.
- **SHOULD**: Recalibrar workers, memoria y conexiones cuando cambie el hardware o la carga.
- **MAY**: Optimizar únicamente ante una medición que identifique un cuello de botella.

## Política de dependencias

- **MUST**: No introducir gestores de secretos dedicados, actualizadores automáticos de imágenes, UIs con privilegios Docker ni mecanismos adicionales de backup.
- **MUST**: Mantener imágenes base con referencias explícitas y evitar tags flotantes.
- **SHOULD**: Preferir dependencias con mantenimiento activo de su vendor o comunidad.

## Convenciones de nombres

- Los servicios y stacks usan minúsculas y el mismo nombre para carpeta, servicio y operación.
- Los archivos Compose usan extensión `.yaml`.
- Las imágenes usan referencias explícitas e identidades inmutables; no se utiliza `latest`.
- Los archivos privados y mutables de cada entorno viven bajo su `runtime/` y las plantillas versionadas quedan junto a ellos.

## Restricciones

- Debe operar en un único servidor, sin depender de alta disponibilidad ni de servicios de gestión adicionales.
- Las operaciones de módulo, instalación, actualización, desinstalación y validación funcional dentro de Odoo permanecen manuales.
- La migración de líneas mayores de Odoo se realiza mediante un checkout aislado, no como una promoción ordinaria.

## Fuera de alcance

- Automatizar pruebas funcionales dentro de Odoo.
- Automatizar la aplicación de imágenes, el reinicio de Odoo o las operaciones de módulos.
- Crear una interfaz, dashboard o sistema de notificaciones específico para la gestión de candidatos e imágenes.

## Registro de enmiendas
