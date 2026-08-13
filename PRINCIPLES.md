# Principios

Las reglas que este stack sigue siempre. Cada una nombra un mecanismo concreto y dice por qué existe: no son buenas prácticas genéricas, son las decisiones que el código de este repositorio ya implementa.

**Obligatorio** — romperlo rompe una garantía del diseño. **Recomendado** — desviarse exige un motivo escrito. **Opcional** — queda a criterio de quien opera.

## Código y configuración

- **Obligatorio.** Pineá todo tag de imagen. `:latest` no se usa nunca: un tag flotante convierte cualquier `pull` en un cambio de versión no revisado.
- **Obligatorio.** Antes de sumar un contenedor, verificá si un servicio ya elegido o una feature nativa de Docker, Postgres o nginx cubre la necesidad. Este stack corre once servicios porque cada uno sobrevivió a esa pregunta.
- **Obligatorio.** Mantené cada entrypoint como archivo base —solo `networks:`, `secrets:` y un `include:` por capa— y una capa por módulo. Nunca un archivo monolítico, y nunca `compose.override.yaml`: ese nombre dispara el autoload implícito de Compose y confunde modularización con override de ambiente.
- **Obligatorio.** Un **entrypoint por entorno**, no un módulo de override que apague capas: Compose no sabe quitar un servicio ya incluido, así que un stack chico tendría que cargar la capa que no quiere para desactivarla. Lo que un entorno sí ajusta de una capa compartida va en su entrypoint con `!reset` o `!override`, al lado del `include:` que la trajo.
- **Obligatorio.** Parametrizá por `.env` todo valor que varía por deployment y se use dentro de un `compose.*.yaml`. Cuando el valor vive en el archivo de config propio de una herramienta, tiene que llegar por el mecanismo que **esa herramienta** ofrezca: env vars que pisan el archivo, interpolación en su propio provisioning, o un entrypoint que lo appendea al conf de runtime. Compose no interpola dentro de archivos bind-mounted.
- **Obligatorio.** Cuando ninguna de esas vías alcanza, eliminá el valor o versionalo literal. No introduzcas archivos `.example` paralelos a un config: son una copia que se desincroniza. La única excepción son las plantillas de `.env` —ver «Estructura»—, que no acompañan a un config versionado sino al archivo que no se versiona, y llevan su propia verificación. Cada herramienta impone su propio mecanismo y no hay uno general: nginx sustituye con `envsubst` sobre `/etc/nginx/templates` y necesita además un filtro que acote qué variables entran, porque si no una env var homónima de una suya (`$host`, `$status`) se la come la sustitución; Loki expande desde su entorno pero solo con `-config.expand-env=true`; pgBackRest no interpola nada y se pisa por variables de entorno opción por opción.
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
- **Obligatorio.** Probá los cambios riesgosos —upgrade mayor, módulo nuevo, cambio de config de la base— en staging antes de aplicarlos a producción. Staging se siembra restaurando el repositorio de producción, así que **sembrarlo y hacer el simulacro de restore son la misma operación**: el ejercicio que si no siempre se posterga tiene ocasión natural.
- **Obligatorio.** Un entorno que no respalda **no archiva WAL**. Apunta a la stanza del que sí para poder restaurar, y con el archivado prendido le empuja su propio WAL al repositorio del entorno real, que es el que después nadie puede reconstruir.
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
- Módulos de Compose: `compose.<capa>.yaml`, uno por capa, y un **entrypoint por entorno** que elige cuáles incluir. `compose.yaml` es el de producción; `compose.staging.yaml` y `compose.dev.yaml` son archivos raíz hermanos, no módulos, y se seleccionan con `COMPOSE_FILE` en `.env`.
- Identidad del stack: `COMPOSE_PROJECT_NAME` y `COMPOSE_FILE` en `.env`, en los tres entornos igual. Ningún archivo de Compose declara `name:`. Del nombre derivan `container_name`, volúmenes, redes y **tags de imagen**: el nombre de una imagen es global al daemon, así que un tag fijo deja que el `build` de un stack pise la imagen que corre otro, sin avisar.
- Valores por deployment: `.env` (no versionado) y una plantilla versionada por entorno —`.env.prod.example`, `.env.stag.example`, `.env.dev.example`—, cada una con las claves de sus capas y sin completar. Son tres copias asumidas: se elige que copiar sea `cp` y nada más, en vez de borrar bloques de un archivo genérico. Lo que las mantiene en sincronía es `make test`, que resuelve cada entrypoint con su plantilla y exige que ninguna variable quede sin declarar.
- Config de runtime de cada herramienta: un directorio por herramienta bajo `config/`. Todo se versiona tal cual. El estado de los certificados **no es un archivo del repositorio**: vive en un volumen nombrado que certbot escribe y nginx monta de solo lectura, así que un cambio de checkout no lo toca.
- Extensiones: la que nombra cada herramienta. Donde hay elección entre `.yml` y `.yaml`, se usa `.yaml`.
- Dockerfiles propios y sus contextos: un directorio por servicio bajo `docker/`.
- Árbol de addons: `addons/.repos/<repo>.git` para el clon bare y `addons/<categoría>/<repo>` para cada worktree. **Un árbol por checkout**, no un subdirectorio por entorno: qué entorno es lo dice `.env`, y superponer los dos aislamientos deja uno que no aísla nada. Todo `addons/` va gitignoreado; el único artefacto versionado es el manifiesto.
- Rol y base de datos de la aplicación: **`odoo`**, fijo. Aparece en los archivos de Compose, en la config de Postgres, de pgBackRest y de la propia aplicación, y en los scripts. Tres de esos formatos no interpolan variables, así que parametrizarlo dejaría la mitad configurable y la otra mitad no — peor que un valor fijo y consistente. El de pgBackRest ni siquiera lo nombra: `pg1-user` llega por entorno desde el mismo archivo de Compose que fija `POSTGRES_USER`.
- Los archivos de Compose y `.env` viven en la **raíz**: Compose los auto-descubre, y moverlos forzaría flags en cada invocación.
