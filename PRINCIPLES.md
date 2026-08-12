# Principios

Las reglas que este stack sigue siempre. Cada una nombra un mecanismo concreto y dice por qué existe: no son buenas prácticas genéricas, son las decisiones que el código de este repositorio ya implementa.

**Obligatorio** — romperlo rompe una garantía del diseño. **Recomendado** — desviarse exige un motivo escrito. **Opcional** — queda a criterio de quien opera.

## Código y configuración

- **Obligatorio.** Pineá todo tag de imagen. `:latest` no se usa nunca: un tag flotante convierte cualquier `pull` en un cambio de versión no revisado.
- **Obligatorio.** Antes de sumar un contenedor, verificá si un servicio ya elegido o una feature nativa de Docker, Postgres o Traefik cubre la necesidad. Este stack corre once servicios porque cada uno sobrevivió a esa pregunta.
- **Obligatorio.** Mantené `compose.yaml` como archivo base —solo `networks:` y `secrets:` compartidos— y sumá un módulo por capa vía `include:`. Nunca un archivo monolítico, y nunca `compose.override.yaml`: ese nombre dispara el autoload implícito de Compose y confunde modularización con override de ambiente.
- **Obligatorio.** Parametrizá por `.env` todo valor que varía por deployment y se use dentro de un `compose.*.yaml`. Cuando el valor vive en el archivo de config propio de una herramienta, tiene que llegar por el mecanismo que **esa herramienta** ofrezca: env vars que pisan el archivo, interpolación en su propio provisioning, o un entrypoint que lo appendea al conf de runtime. Compose no interpola dentro de archivos bind-mounted.
- **Obligatorio.** Cuando ninguna de esas vías alcanza, eliminá el valor o versionalo literal. No introduzcas archivos `.example` paralelos: son una copia que se desincroniza. Algunas herramientas ni siquiera admiten mezclar fuentes — Traefik trata archivo, flags y env vars como mutuamente excluyentes, así que con su archivo presente no hay valor que inyectar por afuera.
- **Recomendado.** Declará `image:` explícito junto a cada `build:`. Sin eso el nombre lo autogenera Compose a partir del nombre del proyecto, y cualquier referencia externa se rompe si el proyecto cambia de nombre.
- **Recomendado.** Preferí configuración expresable en compose o en archivos de config antes que introducir una herramienta nueva.

## Seguridad

- **Obligatorio.** El acceso a cada servicio **desde el host y desde la red física** lo define su bind de publicación —el `ports:`—, nunca el firewall. Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall, así que un `deny` no alcanza a un puerto publicado por un contenedor. Elegí el nivel por quién necesita llegar, y **nunca publiques en `0.0.0.0`**:
  1. **Sin `ports:`** — solo por nombre dentro de su red de Docker. Es el default.
  2. **`127.0.0.1:P:P`** — UIs administrativas y todo endpoint sin autenticación propia; se llega por túnel SSH.
  3. **`${LOCAL_IP}:P:P`** — servicios que atienden clientes de la red local.
  4. **`network_mode: host`** — solo cuando el servicio necesita el stack de red del host; es el único nivel donde el firewall gobierna.

  **Ese criterio no habla de los binds internos del contenedor.** Un proceso que escucha en `0.0.0.0` *dentro* de su contenedor, sin `ports:`, no expone nada al host: solo lo alcanza quien esté en su misma red de Docker, y a veces es necesario —un exporter de métricas tiene que ser scrapeable desde otra red—. Cambiarlo a loopback por aplicar la regla al pie de la letra rompe el scrape sin que nada avise.

- **Obligatorio.** Gobierná el **segundo eje** con la segmentación en redes, no con el bind. Dentro de una red de Docker todo servicio alcanza a todo otro servicio de esa red, sin autenticación de por medio si el servicio no la tiene. Un endpoint sin auth publicado en loopback sigue siendo alcanzable por cualquier contenedor que comparta su red: si eso importa, la respuesta es en qué redes está, no a qué IP publica.
- **Obligatorio.** Hacé pasar todo el tráfico público entrante exclusivamente por el túnel de ingreso hacia el reverse proxy, sin puertos abiertos en el router.
- **Obligatorio.** No le des hostname público a ninguna UI administrativa. Se llega por la red privada de administración, no por internet.
- **Obligatorio.** Gestioná los secretos con `secrets:` nativo de Compose —archivos montados, permisos `640`, grupo del GID del proceso que los lee— y nunca como variables de entorno. Las env vars quedan visibles en `docker inspect` y en `docker exec … env`. El `600` no sirve: Compose fuera de Swarm ignora `uid`/`gid`/`mode` para secrets de archivo, así que un `600` root-owned deja sin lectura a cualquier contenedor no-root.
- **Obligatorio.** Terminá TLS con certificado propio en el reverse proxy, sin depender de que el borde del CDN lo termine. El acceso por red local esquiva ese borde por completo.
- **Obligatorio.** Poné rate-limiting en el login a nivel de red, antes de que el tráfico llegue a la aplicación.
- **Obligatorio.** Segmentá los contenedores en redes separadas por función, para acotar el radio de impacto si uno se compromete.
- **Obligatorio.** Montá el socket de Docker **solo lectura** y únicamente donde hace falta para descubrimiento u observación. Nunca en algo que acepte comandos del operador o de la red.
- **Recomendado.** Acotá los tokens de API al permiso mínimo y a la zona o recurso específico. Nunca claves globales de cuenta.
- **Recomendado.** Corré los contenedores como usuario no-root donde la imagen base lo soporte. Cuando no se pueda, registrá cuál y por qué.

## Operación

- **Obligatorio.** Corré backups en cadencia definida, con la ventana de retención de la base y la del filestore **alineadas**: un restore de una necesita contraparte consistente en la otra.
- **Obligatorio.** La capa de backups es **exclusiva del entorno productivo**. Un segundo stack levantado desde los mismos archivos escribiría en el mismo repositorio remoto y en los mismos archivos de estado del host, y su corrida apagaría la alerta de backup viejo del entorno real. Un entorno descartable no tiene qué respaldar.
- **Obligatorio.** Respaldá siempre la base primero y el filestore después. Un snapshot de filestore más nuevo deja archivos huérfanos, que son inofensivos; uno más viejo deja filas apuntando a archivos inexistentes, que es destructivo y silencioso.
- **Obligatorio.** Hacé las actualizaciones de imágenes y módulos a mano. Sin Watchtower ni equivalente: un cambio de versión exige leer release notes antes de aplicarse.
- **Obligatorio.** Instalar o actualizar un módulo en la base es un paso **explícito del operador**, nunca atado al arranque del contenedor. Un `-u` de varios minutos disparado en cada boot se repite en el restart automático de un crash, alargando la caída en vez de resolverla.
- **Obligatorio.** Hacé al menos un simulacro completo de restore —base y filestore— periódicamente. Un backup sin probar no es un backup.
- **Obligatorio.** Forzá los límites de recursos por contenedor en los archivos de compose. El presupuesto de memoria tiene que estar garantizado a nivel Docker, no ser un plan en papel.
- **Obligatorio.** Probá los cambios riesgosos —upgrade mayor, módulo nuevo, cambio de config de la base— en un clon ad hoc de base y filestore bajo otro nombre de proyecto, antes de aplicarlos a producción.
- **Recomendado.** Declará healthcheck y `restart: unless-stopped` en cada contenedor: el restart de Docker es el único mecanismo de auto-recuperación, porque no hay orquestador externo.
- **Recomendado.** Recalibrá los valores derivados del hardware —workers, memoria de la base, límites de conexión— cuando cambie el hardware o la escala de uso. Se calcularon juntos: revisá la tabla entera, no la fila que parece afectada.

## Observabilidad

- **Obligatorio.** Recolectá métricas de host, de contenedores y de la base, más logs centralizados y consultables.
- **Obligatorio.** La caída del agente de recolección no puede silenciar las alertas de disponibilidad. Lo que ya expone métricas por HTTP se scrapea por pull, y el propio agente es un target más. Si todo se empuja por el agente, su muerte no dispara nada: las series dejan de llegar, y un umbral sobre una serie ausente no alerta.
- **Obligatorio.** Declará retención **explícita y acotada** en el almacén de métricas y en el de logs. Sin techo crecen hasta llenar el mismo disco del que dependen la base y los backups.
- **Obligatorio.** Capturá las métricas de capa de aplicación —latencia y tasa de error—. Los exporters de infraestructura no cubren esa capa.
- **Obligatorio.** Corré el alerting con notificación efectiva a un canal que alguien mire. Sin eso el stack de observabilidad es puramente pasivo.
- **Obligatorio.** Definí datasources, dashboards y recursos de alerting **como código** versionado, no como estado clickeado en la UI que se pierde al recrear el contenedor.
- **Recomendado.** Configurá rotación de logs como default del daemon de Docker, para cubrir todo contenedor presente y futuro sin repetir el bloque por servicio. Es la red aparte contra un incidente de logging descontrolado, que la retención del almacén de logs no frena.

## Dependencias

- **Obligatorio.** Verificá si un servicio ya elegido, una feature nativa o un script cubre la necesidad antes de sumar algo nuevo.
- **Obligatorio.** No introduzcas un secrets manager dedicado, una UI de gestión con privilegio sobre el socket de Docker, un mecanismo de auto-update, ni herramientas de backup adicionales a las dos ya elegidas.
- **Recomendado.** Ante dos alternativas que resuelven lo mismo, preferí la que tenga respaldo de comunidad o vendor activo.

## Convenciones de nombres

- Servicios de Compose: minúsculas, singular donde se pueda.
- Secretos: un archivo por credencial bajo `secrets/`, `640`, grupo del GID que lo consume.
- Tags de imagen: siempre versión explícita.
- Módulos de Compose: `compose.<capa>.yaml`, uno por capa. `compose.staging.yaml` y `compose.dev.yaml` quedan fuera del `include:` por defecto.
- Valores por deployment: `.env` (no versionado) y `.env.example` (versionado, con las claves sin completar).
- Config de runtime de cada herramienta: un directorio por herramienta bajo `config/`. Todo se versiona tal cual; el único archivo no trackeado es el estado de runtime del resolver ACME.
- Extensiones: la que nombra cada herramienta. Donde hay elección entre `.yml` y `.yaml`, se usa `.yaml`.
- Dockerfiles propios y sus contextos: un directorio por servicio bajo `docker/`.
- Árbol de addons: `addons/.repos/<repo>.git` para el clon bare y `addons/<categoría>/<repo>` para cada worktree. **Un árbol por checkout**, no un subdirectorio por entorno: qué entorno es lo dice `.env`, y superponer los dos aislamientos deja uno que no aísla nada. Todo `addons/` va gitignoreado; el único artefacto versionado es el manifiesto.
- Rol y base de datos de la aplicación: **`odoo`**, fijo. Aparece en los archivos de Compose, en la config de Postgres, de pgBackRest y de la propia aplicación, y en los scripts. Tres de esos formatos no interpolan variables, así que parametrizarlo dejaría la mitad configurable y la otra mitad no — peor que un valor fijo y consistente. El único que sí puede desincronizarse, el nombre de la stanza de backup, lo verifica `make verify-db`.
- Los archivos de Compose y `.env` viven en la **raíz**: Compose los auto-descubre, y moverlos forzaría flags en cada invocación.
