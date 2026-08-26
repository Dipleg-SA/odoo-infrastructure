# Principios

Las reglas que este stack sigue siempre. Cada una nombra un mecanismo concreto y dice por qué existe: no son buenas prácticas genéricas, son las decisiones que el código de este repositorio ya implementa.

Una regla enuncia una **restricción**, no una forma del árbol. Un principio que nombra una carpeta caduca con la próxima reorganización; uno que nombra un límite de la herramienta no caduca nunca. La forma vive en [`docs/modular-architecture.md`](docs/modular-architecture.md).

**Obligatorio** — romperlo rompe una garantía del diseño. **Recomendado** — desviarse exige un motivo escrito. **Opcional** — queda a criterio de quien opera.

## Composición

- **Obligatorio.** Un stack es **un contenedor que corre**, con todo lo suyo en su carpeta. Un contenedor que solo se invoca a mano no es un stack: vive dentro del que sirve, porque darle configuración, verificación y entorno propios es andamiaje para algo que existe treinta segundos.
- **Obligatorio.** Componé sumando, nunca apagando. Compose no sabe quitar un servicio de un archivo ya incluido, así que un entorno chico no puede cargar una composición grande para desactivarle partes: lista lo que lleva. Nunca un archivo monolítico, y nunca `compose.override.yaml` —ese nombre dispara el autoload implícito de Compose y confunde modularización con override de ambiente—.
- **Obligatorio.** Lo que un stack comparte con otro lo declara el entorno; lo que es solo suyo lo declara el stack. Compose **fusiona en silencio, con exit 0**, las declaraciones divergentes de un mismo recurso que llegan por distintos `include:`: un stack que declare una red compartida con otras opciones se las impone al resto sin que nada avise, y el error aparece en producción, no en `config`. Una sola definición elimina esa clase entera de fallas.
- **Obligatorio.** Lo que un entorno ajusta de un stack va en su entrypoint, con `!reset` o `!override`, al lado del `include:` que lo trajo. Un stack no lleva condicionales por entorno adentro.
- **Obligatorio.** Elegí el mecanismo por lo que pasa cuando algo se activa por accidente: **composición** donde eso sería destructivo y silencioso, **`profiles`** donde sería ruidoso e inofensivo. Un servicio ausente no puede activarse por una variable mal puesta; uno que falla al arrancar avisa solo.
- **Obligatorio.** Pineá todo tag de imagen. `:latest` no se usa nunca: un tag flotante convierte cualquier `pull` en un cambio de versión no revisado.
- **Obligatorio.** Antes de sumar un contenedor, verificá si un servicio ya elegido o una feature nativa de Docker, Postgres o nginx cubre la necesidad. Cada servicio que corre sobrevivió a esa pregunta.
- **Recomendado.** Declará `image:` explícito junto a cada `build:`. Sin eso el nombre lo autogenera Compose a partir del nombre del proyecto, y cualquier referencia externa se rompe si el proyecto cambia de nombre.

## Configuración

- **Obligatorio.** En un `.env` va **solo lo que Compose necesita interpolar**. Todo lo demás va literal en el archivo de config de la herramienta que lo usa. La pregunta "¿dónde va este valor?" tiene entonces una respuesta mecánica y no un juicio, y un valor que usan tres herramientas deja de ser una copia que puede divergir para ser tres herramientas configuradas cada una en su idioma.
- **Obligatorio.** Cuando el valor sí tiene que llegar desde afuera, tiene que hacerlo por el mecanismo que **esa herramienta** ofrezca: env vars que pisan el archivo, interpolación en su propio provisioning, o un entrypoint que lo appendea al conf de runtime. Compose no interpola dentro de archivos bind-mounted, y cada herramienta impone lo suyo — Loki expande desde su entorno solo con `-config.expand-env=true`; hay herramientas que no interpolan nada y solo se pisan por variables de entorno opción por opción; nginx sustituye con `envsubst` y necesita además un filtro que acote qué variables entran, porque si no una env var homónima de una suya (`$host`, `$status`) se la come la sustitución.
- **Obligatorio.** Un config que varía por deployment se versiona como plantilla y se bootstrapea con `cp`; el archivo real queda sin versionar, al lado de su plantilla, y el operador lo edita a mano. Un config que **no** lleva ningún valor por deployment se versiona tal cual: una plantilla de sí mismo es una copia que se desincroniza.
- **Obligatorio.** Cuando ninguna vía alcanza, eliminá el valor o versionalo literal.

## Seguridad

- **Obligatorio.** El acceso a cada servicio **desde el host y desde la red física** lo define su bind de publicación —el `ports:`—, nunca el firewall. Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall, así que un `deny` no alcanza a un puerto publicado por un contenedor. Elegí el nivel por quién necesita llegar, y **nunca publiques en `0.0.0.0`**:
  1. **Sin `ports:`** — solo por nombre dentro de su red de Docker. Es el default.
  2. **`127.0.0.1:P:P`** — UIs administrativas y todo endpoint sin autenticación propia; se llega por túnel SSH.
  3. **`${LOCAL_IP}:P:P`** — servicios que atienden clientes de la red local.
  4. **`network_mode: host`** — solo cuando el servicio necesita el stack de red del host; es el único nivel donde el firewall gobierna.

  **Ese criterio no habla de los binds internos del contenedor.** Un proceso que escucha en `0.0.0.0` *dentro* de su contenedor, sin `ports:`, no expone nada al host: solo lo alcanza quien esté en su misma red de Docker, y a veces es necesario —un exporter de métricas tiene que ser scrapeable desde otra red—. Cambiarlo a loopback por aplicar la regla al pie de la letra rompe el scrape sin que nada avise.

- **Obligatorio.** Gobérná el **segundo eje** con la segmentación en redes, no con el bind. Dentro de una red de Docker todo servicio alcanza a todo otro servicio de esa red, sin autenticación de por medio si el servicio no la tiene. Un endpoint sin auth publicado en loopback sigue siendo alcanzable por cualquier contenedor que comparta su red: si eso importa, la respuesta es en qué redes está, no a qué IP publica.
- **Obligatorio.** Hacé pasar todo el tráfico público entrante exclusivamente por el túnel de ingreso hacia el reverse proxy, sin puertos abiertos en el router.
- **Obligatorio.** No le des hostname público a ninguna UI administrativa. Se llega por la red privada de administración, no por internet.
- **Obligatorio.** Gestioná los secretos con `secrets:` nativo de Compose —archivos montados, permisos `640`, grupo del GID del proceso que los lee— y nunca como variables de entorno. Las env vars quedan visibles en `docker inspect` y en `docker exec … env`. El `600` no sirve: Compose fuera de Swarm ignora `uid`/`gid`/`mode` para secrets de archivo, así que un `600` root-owned deja sin lectura a cualquier contenedor no-root.
- **Obligatorio.** Acotá cada credencial al permiso mínimo que su portador necesita. No es solo higiene: es lo que convierte una regla de procedimiento en una garantía. Un entorno que solo tiene que **leer** un repositorio de backups lleva una credencial de solo lectura, y entonces no puede escribirlo aunque alguien corra el comando equivocado — la escritura falla en el proveedor, no en un `if`.
- **Obligatorio.** Terminá TLS con certificado propio en el reverse proxy siempre que haya tráfico que no pase por el borde del CDN. El acceso por red local lo esquiva por completo; donde no existe ese acceso, tampoco existe ese requisito.
- **Obligatorio.** Poné rate-limiting en el login a nivel de red, antes de que el tráfico llegue a la aplicación, y dentro de este stack: un control delegado al borde del CDN deja de ser algo que este repositorio garantiza.
- **Obligatorio.** Segmentá los contenedores en redes separadas por función, para acotar el radio de impacto si uno se compromete.
- **Obligatorio.** Montá el socket de Docker **solo lectura** y únicamente donde hace falta para descubrimiento u observación. Nunca en algo que acepte comandos del operador o de la red.
- **Recomendado.** Corré los contenedores como usuario no-root donde la imagen base lo soporte. Cuando una operación puntual necesite root, elevala en la invocación —no en la declaración del servicio— para que la operación recurrente siga siendo no-root.

## Operación

- **Obligatorio.** Respaldá la base y el filestore **en el mismo snapshot**. Son dos mitades de un mismo estado: la base referencia archivos que solo existen en el filestore, y respaldarlos por separado convierte la consistencia en un procedimiento que hay que recordar en vez de una propiedad del backup.
- **Obligatorio.** Dimensioná el RPO con la **frecuencia del snapshot**, no con archivado continuo. El archivado de WAL da granularidad sobre la base, pero el filestore no tiene equivalente: restaurar la base más adelante que el último snapshot del filestore deja filas apuntando a archivos que nunca se respaldaron.
- **Recomendado.** Vigilá el tiempo del respaldo, no su tamaño. Un dump relee la base entera en cada corrida: cuando ese tiempo cruza el umbral tolerable, la estrategia de snapshot dejó de alcanzar y toca reconsiderarla. Que lo avise el propio script, para que la decisión no dependa de que alguien mire.
- **Obligatorio.** Un entorno descartable no respalda. Levantado desde los mismos archivos escribiría en el mismo repositorio remoto y en los mismos archivos de estado del host, y su corrida apagaría la alerta de backup viejo del entorno real.
- **Obligatorio.** Hacé las actualizaciones de imágenes y módulos a mano. Sin Watchtower ni equivalente: un cambio de versión exige leer release notes antes de aplicarse.
- **Obligatorio.** Instalar o actualizar un módulo en la base es un paso **explícito del operador**, nunca atado al arranque del contenedor. Un `-u` de varios minutos disparado en cada boot se repite en el restart automático de un crash, alargando la caída en vez de resolverla.
- **Obligatorio.** Hacé al menos un simulacro completo de restore periódicamente. Un backup sin probar no es un backup. Restaurar en una máquina distinta de la de origen es el simulacro más fuerte: prueba que el respaldo es portable y que no depende en secreto de algo que solo existe en el servidor original.
- **Obligatorio.** Forzá los límites de recursos por contenedor en los archivos de compose. El presupuesto de memoria tiene que estar garantizado a nivel Docker, no ser un plan en papel.
- **Obligatorio.** Probá los cambios riesgosos —upgrade mayor, módulo nuevo, cambio de config de la base— en un entorno de prueba antes de aplicarlos a producción. Ese entorno se siembra restaurando el respaldo de producción, así que **sembrarlo y hacer el simulacro de restore son la misma operación**: el ejercicio que si no siempre se posterga tiene ocasión natural.
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
- **Obligatorio.** No introduzcas un secrets manager dedicado, una UI de gestión con privilegio sobre el socket de Docker, un mecanismo de auto-update, ni una herramienta de backup adicional a la ya elegida.
- **Recomendado.** Ante dos alternativas que resuelven lo mismo, preferí la que tenga respaldo de comunidad o vendor activo.

## Convenciones de nombres

- **Un stack se llama como su contenedor.** No hay traducción entre lo que se tipea, lo que se ve en el árbol y lo que corre.
- Servicios de Compose: minúsculas, singular donde se pueda.
- Secretos: un archivo por credencial bajo `secrets/`, `640`, grupo del GID que lo consume.
- Tags de imagen: siempre versión explícita.
- Identidad del stack: `COMPOSE_PROJECT_NAME` y `COMPOSE_FILE` en `.env`, igual en todos los entornos. Ningún archivo de Compose declara `name:`. Del nombre derivan `container_name`, volúmenes, redes y **tags de imagen**: el nombre de una imagen es global al daemon, así que un tag fijo deja que el `build` de un stack pise la imagen que corre otro, sin avisar.
- Valores por deployment: `.env` no versionado, con una plantilla versionada por entorno, cada una con las claves de su composición y sin completar. Son copias asumidas: se elige que copiar sea `cp` y nada más, en vez de borrar bloques de un archivo genérico. Lo que las mantiene en sincronía es `make test`, que resuelve cada entrypoint con su plantilla y exige que ninguna variable quede sin declarar.
- Config de runtime, plantillas, `Dockerfile`, scripts y units de systemd de un stack: **adentro de la carpeta de ese stack**, incluidas las que se instalan fuera del checkout. Arriba solo lo que sirve a más de uno.
- Estado que no es un archivo del repositorio —certificados, datos— vive en volúmenes nombrados, así que un cambio de checkout no lo toca.
- Extensiones: la que nombra cada herramienta. Donde hay elección entre `.yml` y `.yaml`, se usa `.yaml`.
- Árbol de addons: un clon bare por repo y un worktree por categoría. **Un árbol por checkout**, no un subdirectorio por entorno: qué entorno es lo dice `.env`, y superponer los dos aislamientos deja uno que no aísla nada. Todo va gitignoreado; lo versionado son las plantillas del manifiesto y de los pines Python que se derivan de él.
- Rol y base de datos de la aplicación: **`odoo`**, fijo. Aparece en los archivos de Compose, en la config de Postgres, en la de la propia aplicación y en los scripts. Varios de esos formatos no interpolan variables, así que parametrizarlo dejaría la mitad configurable y la otra mitad no — peor que un valor fijo y consistente.
- `.env` vive en la **raíz**, y los archivos de Compose no. Compose lee `.env` del directorio donde se corre el comando, no del que contiene el archivo elegido, así que `COMPOSE_FILE` alcanza y ninguna invocación lleva flags. Al no quedar ningún `compose.yaml` auto-descubrible en la raíz, un checkout sin `.env` falla con `no configuration file provided` en vez de resolver producción con variables vacías.
