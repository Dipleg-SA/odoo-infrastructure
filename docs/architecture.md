# Arquitectura

Por qué cada herramienta y no otra. Registra la decisión, su motivo y las alternativas descartadas — las reglas que se desprenden están en [`PRINCIPLES.md`](../PRINCIPLES.md).

## Objetivo de robustez

Con un solo servidor, "robusto" prioriza en este orden:

1. **Evitar pérdida de datos.**
2. **Visibilidad operativa** — detectar y diagnosticar caídas rápido.

Alta disponibilidad real queda fuera de alcance: no es alcanzable con un único servidor, así que ninguna decisión se toma para acercarse a ella.

---

## Backups

**El requisito que lo dispara:** poder recuperar a un momento específico del día, no solo a la última foto nocturna.

**Storage: Cloudflare R2.** El motivo principal es que no cobra egress, y en backups el costo real aparece al *restaurar* — justo en el momento de un desastre. Descartados: S3 (maduro pero cobra egress, un costo inesperado durante una recuperación real) y Backblaze B2 (barato, pero un proveedor separado más que gestionar).

**Base de datos: pgBackRest.** Archivado continuo de WAL vía `archive_mode`/`archive_command` da un RPO de minutos para la base. Sube directo a storage S3-compatible, sin herramienta de transporte adicional.

El binario corre **dentro del contenedor de Postgres**, no en uno aparte: el `archive_command` lo ejecuta el propio proceso de la base, así que tiene que estar ahí de todas formas. Se descartó la topología de *repo host* dedicado — en modo TLS pgBackRest exige un servidor corriendo en ambos lados, lo que suma un sidecar y una PKI propia, y el aislamiento de credenciales que la justificaba queda parcial igual porque ese sidecar lee el directorio de datos en crudo.

**Filestore: restic.** Deduplicación real y cifrado nativo. Los adjuntos se acumulan y casi no cambian una vez escritos, así que la dedup ahorra espacio de forma significativa.

**Retención.** Los dos modelos son distintos: pgBackRest retiene *backups full*, y al expirar uno caen en cascada sus diferenciales dependientes; el WAL se deja atado automáticamente a esa ventana para no caer en la trampa de borrar WAL que todavía hace falta. restic retiene por conteo de diarios, semanales y mensuales.

Lo que fija el número no es una preferencia: **la ventana de la base tiene que cubrir al menos la del filestore**. Un restore de la base a un día puntual necesita un snapshot de filestore de esa misma fecha; si la base cubriera menos, la cola larga del filestore quedaría inútil para una restauración completa. La cadencia es full mensual más diferencial diario —no full semanal— para sostener esa ventana sin acumular varias copias completas.

**La capa es exclusiva de producción.** Los entornos no productivos no la incluyen. No es una simplificación: comparten el repositorio remoto, la stanza y los archivos de estado del host, así que la corrida de un entorno descartable escribiría la marca de éxito que apaga la alerta del entorno real. Y no hay nada que proteger — un stack que se destruye después de usarse no acumula datos.

| Qué | Herramienta | Dónde | Se restaura con |
|---|---|---|---|
| Base de datos (cluster completo) | pgBackRest | R2, prefijo `pgbackrest/` | servicio `restore-db` (misma imagen que `postgres`, uid 999) |
| Filestore (adjuntos) | restic | R2, prefijo `restic/` | servicio `restore-files` (uid 100:101, monta `odoo-data` rw) |

**pgBackRest restaura el cluster entero**, no una base suelta: no existe "restaurar solo la tabla X" ni "solo la base `odoo`". Y **los dos servicios de restore duermen** (`entrypoint: sleep infinity`) — levantarlos no restaura nada, son contenedores donde el operador ejecuta los comandos a mano; están fuera de `make up` por `profiles: [restore]`.

### Consistencia entre base y filestore

Los adjuntos viven partidos: la fila en la base, el archivo en el filestore. **Un restore desalineado es la falla silenciosa de este sistema** — la base arranca sana y el problema aparece meses después, cuando alguien abre un documento viejo.

- **Orden obligatorio en cada corrida: la base primero, el filestore después.** Un filestore más nuevo deja archivos huérfanos, que son inofensivos; uno más viejo deja filas apuntando a archivos inexistentes, que es destructivo. El orden garantiza que el snapshot sea siempre un superconjunto de lo que la base referencia.
- **El filestore vivo no reemplaza a un snapshot.** El recolector de basura de Odoo borra archivos que ninguna fila referencia, así que un estado pasado de la base puede referenciar archivos ya limpiados.
- **El RPO combinado lo acota la cadencia del filestore**, no el WAL. Se evaluó y descartó subirla: el escenario que eso cubre exige que se junten pérdida total del disco *y* recuperación a media tarde, mientras que en el escenario dominante —error lógico con el disco intacto— la cadencia no interviene.
- **Contrapartida obligatoria:** el procedimiento de restore incluye un chequeo de integridad entre las referencias de la base y el filestore, que convierte una falla silenciosa en un diagnóstico inmediato.

### El riesgo aceptado: dos copias, no 3-2-1

El diseño entrega la copia viva y una offsite. El escenario no cubierto no es "se rompió el proveedor" —su durabilidad es alta— sino **perder acceso a la cuenta**: facturación, suspensión, token revocado. Como el mismo proveedor da el túnel de ingreso y el DNS, ese evento deja el sistema sin ingreso *y* sin backups el mismo día.

Y hay que decirlo sin adornos: **no hay mitigación efectiva contra el borrado de los backups.** Un token sin permiso de borrado rompe el diseño, porque la retención necesita borrar para funcionar; y R2 no soporta versioning de objetos. Quien tenga la credencial puede vaciar el bucket, y la única defensa real sería una segunda copia en otro proveedor.

**Descartados:** volcado periódico más cron como único mecanismo (RPO de hasta 24 h, no cumple el requisito); Duplicati (no aporta nada sobre lo elegido y suma un proceso y una base de metadata propios); `rclone` como mecanismo de backup en sí (las dos herramientas ya suben nativo a S3-compatible).

---

## Borde y red

**Ingreso: túnel saliente hacia el borde del CDN.** Conexión desde el servidor hacia afuera, sin puertos abiertos en el router, sin exponer la IP pública, y con filtrado de tráfico malicioso antes de llegar a la red local. Descartados: exposición directa del `80`/`443` en el router, y usar el CDN solo como DNS.

El túnel se administra desde el dashboard del proveedor, así que el mapeo de hostname público a servicio interno **no queda como código en este repositorio**. Es la única pieza del borde en esa situación, y es una consecuencia asumida.

**Modelo de exposición:** solo la aplicación tiene hostname público. Ninguna UI administrativa lo recibe — reduce quién puede siquiera intentar llegar a un login, sin importar qué tan bueno sea ese login.

### El criterio de bind

El hallazgo que lo motiva: **Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall**, así que un `deny` no bloquea un puerto publicado por un contenedor. El bind, en cambio, es control del kernel: no hay regla que lo saltee.

De ahí los cuatro niveles —sin `ports:`, loopback, IP de la LAN, `network_mode: host`— y la prohibición de `0.0.0.0`. El firewall del host queda acotado a lo que sí gobierna: los puertos de procesos del host.

**La red privada de administración llega al servidor, no a los servicios.** Ningún contenedor se ata a su IP. Además de acotar la superficie, evita un modo de falla concreto: ese bind falla con `cannot assign requested address` si la interfaz no está arriba cuando Docker levanta el contenedor, y con `restart: unless-stopped` el servicio queda en loop tras un reboot.

**Reverse proxy: nginx.** Config en archivos, no descubrimiento por labels. La elección se revisó al planificar el segundo y el tercer entorno, y ahí el auto-discovery deja de ser una ventaja: el provider de Docker no está acotado al proyecto, así que con dos stacks en el mismo host cada proxy descubre los contenedores del otro y arma routers duplicados hacia backends que no alcanza. Config estática lo vuelve imposible por construcción, y además saca el socket de Docker de un servicio expuesto a internet.

Se paga en dos monedas. **Los certificados dejan de ser gratis:** nginx no hace ACME, así que aparece certbot como componente nuevo, con su propio timer y su propio modo de falla — una renovación que falla en silencio, que es lo que cubre el `OnFailure=`. Y **las métricas de capa de aplicación hay que reconstruirlas:** nginx OSS solo expone `stub_status` —conexiones y un contador de requests, sin latencia ni códigos—, así que la latencia y la tasa de error salen del access log en JSON, consultado desde Loki. Se descartó un exporter que parsee ese log a métricas de Prometheus: es técnicamente mejor y no justifica un contenedor más.

El mismo nginx corre en los tres entornos, sin TLS en desarrollo. Que el proxy exista también ahí es deliberado: es lo que hace honesto al `proxy_mode = True` de `odoo.conf`, que sin nadie escribiendo `X-Forwarded-*` confía en cabeceras que no existen.

**Acceso por red local: `dnsmasq`.** Resuelve el mismo hostname a la IP local para los dispositivos de la red. Preferido sobre Pi-hole o AdGuard Home, más pesados y con funciones no pedidas para un problema que se resuelve con una línea de config. Beneficio adicional para el objetivo de robustez: **este camino no depende del túnel ni de internet**. Salvedad: esquiva el filtrado del borde, así que es una postura de seguridad distinta a la del acceso público.

**TLS: certificado propio vía desafío DNS-01.** No alcanza con que el CDN termine TLS en su borde, porque el acceso por red local lo evita por completo. DNS-01 y no HTTP-01 porque no requiere el puerto 80 público — compatible con cero puertos abiertos. El resultado es cifrado de punta a punta en los tres tramos.

**Fuerza bruta en el login: rate-limit en el proxy.** Cuenta requests sin importar éxito o fallo, así que frena tráfico automatizado de alto volumen antes de que llegue a la aplicación. Se verificó que el rate-limiting que documenta Odoo es específico de su nube y no viene en una instalación autoalojada — de ahí el ecosistema de módulos de terceros para agregarlo.

---

## Capa de datos

**Redis: no.** Se evaluó como backend del bus de notificaciones, que por defecto usa `LISTEN/NOTIFY` de Postgres. El worker gevent que maneja el bus queda siempre en un proceso, sin importar la cantidad de workers HTTP, así que no escala con ellos. Lo que justificaría Redis es volumen alto de notificaciones concurrentes o varias instancias compartiendo el bus; con un solo servidor no aplica ninguno. Agregarlo después es un parámetro de config, sin rearmar nada.

**PgBouncer: sí, con el módulo de conexión alternativa para el bus.** Sin pooler, el límite de conexiones por proceso de Odoo da un techo teórico muy por encima del `max_connections` de Postgres. Tunear ese límite a mano resuelve el síntoma, pero es una cuenta a rehacer cada vez que cambie la cantidad de workers.

El setup es de **dos puertos**: los workers HTTP y los de cron conectan al pooler en **modo transacción**, que es donde está el multiplexado real; el worker gevent conecta **directo a Postgres**, porque el modo transacción rompe `LISTEN/NOTIFY` y con eso el chat en tiempo real. Alternativas descartadas: modo sesión sin el módulo (no rompe el bus, pero cede el multiplexado que es la razón de sumar el pooler) y modo transacción sin el módulo (regresión funcional real).

**Autenticación del pooler: contraseña en el archivo, no consultada a la base.** PgBouncer lee las credenciales de un archivo propio, así que la contraseña de la aplicación queda en texto plano dentro de él. Se acepta porque ese archivo es un secret con permisos `640` y grupo del proceso que lo lee, y porque el pooler no publica puerto: alcanzarlo exige ya estar en su red de Docker. La alternativa es que el pooler consulte la contraseña a la base en cada conexión, lo que elimina la copia y simplifica la rotación, a cambio de un rol adicional con permiso de lectura sobre el catálogo de autenticación. Se revisita si la rotación de esa credencial pasa a ser frecuente.

**El tamaño del pool se calcula, no se elige.** Con Odoo procesando una request a la vez por worker, el pico teórico de transacciones simultáneas es la suma de workers HTTP más threads de cron. El pool se dimensiona sobre ese pico con margen, y el límite de clientes se deja generoso para no tener que retocar también el de Odoo.

**Versión de Postgres:** la estable más reciente compatible, no la mínima. Al no tratarse de una migración desde una versión vieja, maximiza el tiempo antes de quedar desactualizada.

**Tuning de memoria.** Lo que importa es el método, no los números: los parámetros se calculan **como ratio del cap de memoria del contenedor, no de la RAM del host**. Postgres no es el inquilino principal —la aplicación lo es— así que se lo acota con un `mem_limit` explícito y el resto se deriva de ahí. `effective_cache_size` es una pista para el planner, no una reserva, y se deja conservador porque la page cache del sistema se comparte con todo lo demás.

---

## Aplicación

**Workers: por debajo de lo que da la fórmula.** La fórmula estándar asume que la aplicación tiene el servidor para ella sola. Cuando comparte host con la base, el resto del stack y cualquier otra cosa, el número se ajusta hacia abajo y se acompaña de límites de memoria por proceso, más un `mem_limit` de contenedor que cubra la suma con margen — para que el reciclado propio de Odoo gane al OOM-kill de Docker.

**`proxy_mode` habilitado.** No es una decisión con alternativa real: se desprende de tener un reverse proxy adelante. Sin eso, Odoo no detecta correctamente HTTPS ni la IP de origen.

**SMTP: servicio transaccional de terceros.** Mismo patrón que usar storage gestionado en vez de mantenerlo uno mismo — reputación de IP, SPF, DKIM y DMARC ya resueltos, evitando el riesgo de deliverability de un servidor de correo autoalojado.

Se configura como servidor saliente por defecto en el archivo de config, y no como registro en la base desde la UI: ese registro es estado que no sobrevive a un rebuild ni se expresa como código, mientras que el default del archivo es config versionada. Regla operativa que se desprende: no crear servidores salientes desde la interfaz.

**Upgrade de versión mayor.** En la edición comunitaria, la vía es el proyecto de migración de la comunidad, porque el fabricante no ofrece servicio oficial para esa edición. Detalle práctico: los scripts de migración suelen tardar cerca de un año en madurar tras cada release, lo que conviene tener en cuenta al planificar.

### Gestión de addons: bind-mount

Los módulos **no se hornean en la imagen**: se montan `:ro` desde un árbol en disco.

**El motivo es el costo de deploy.** Con los repos pineados a commit dentro de la imagen, cambiar una línea de un módulo propio costaba cinco pasos —commit en el módulo, bump del hash, commit acá, rebuild, restart—, o sea un ciclo de build completo por cada corrección. Con bind-mount son dos: sincronizar el árbol y actualizar el módulo en la base. El pineo era proporcionado para módulos de terceros, que casi no se mueven, y desproporcionado para los propios en desarrollo activo.

**El pineo no se pierde: cambia de naturaleza.** Deja de ser una declaración mantenida a mano y pasa a ser una **observación registrada automáticamente** — la corrida de backup vuelca repo, rama y commit de cada worktree dentro del snapshot, así que un restore sabe a qué código volver sin que nadie tenga que acordarse en cada deploy.

**Un repo por módulo, dos ramas fijas por entorno.** Producción y staging, con el desarrollo en ramas de feature. La rama de staging se resetea a la de producción antes de cada feature, así que staging es siempre *producción más exactamente un cambio* y queda **descartable en todo momento**: nunca contiene nada que no exista además en una rama de feature o en producción. Eso permite serializar features sin cherry-picks, porque promover sube exactamente lo que se validó.

**Los módulos de terceros se forkean a la organización propia**, con el original como segundo remote. Un solo modelo para todos los repos, y habilita parchear un módulo ajeno sin salir de él — que era el argumento fuerte a favor de una herramienta agregadora y la razón por la que se habían descartado los submodules. Lo que se pierde a conciencia es combinar una rama base con PRs sueltos sin mergear; con forks eso se resuelve mergeando el PR en la rama propia: más trabajo manual, sin una herramienta que mantener, y con el resultado visible en el historial.

**El servidor es réplica de solo lectura.** Todos los merges ocurren en la máquina del operador; el servidor solo trae cambios. Nada de lo que hay en ese disco es irrecuperable, y por eso la credencial de git es de solo lectura.

**Sobrevive un Dockerfile mínimo.** Se evaluó eliminar el build por completo y se descartó: los módulos declaran dependencias de Python, y sin imagen propia no hay dónde instalarlas. El build queda disparado solo por un cambio de dependencias o del entrypoint, nunca por un addon — que es exactamente lo que se buscaba.

**Precedencia si dos módulos coinciden en nombre:** `enterprise` > `custom-addons` > `oca` > `third-party` > core. La arma el entrypoint recorriendo las categorías en ese orden, por glob y no por un listado a mano. **Advertencia:** Odoo no documenta la precedencia del `addons_path`; este orden se apoya en convención, no en una fuente normativa.

---

## Observabilidad

Se evalúa herramienta por herramienta, no como stack cerrado.

**Prometheus y Grafana: sí.** Lo que se busca es ver tendencias históricas —si la memoria viene subiendo hace días o fue un pico— y no solo el estado actual. Sin Grafana, ese histórico solo se consulta con queries manuales, lo que contradice el motivo de sumar Prometheus.

**Colectores de host, de contenedores y de la base: sí, pero no como contenedores separados.** Un único agente los embebe como componentes nativos: son los mismos colectores, con los mismos nombres de métrica, así que los dashboards prearmados siguen sirviendo. Es el principio de "verificar si algo ya elegido cubre la necesidad" aplicado **antes** de sumar tres contenedores, no después. Los tres se complementan: el de host da el total, el de contenedores desglosa cuál servicio consume, y el de la base responde el *por qué* detrás de ese *cuánto*.

**Logs centralizados: sí.** Se prioriza tenerlos buscables junto a las métricas por sobre el ahorro de un par de contenedores. El mismo agente que recolecta métricas los envía; el agente de logs que tradicionalmente cumplía ese rol está descontinuado y su sucesor es justamente ese agente único.

**La topología es híbrida, y no por gusto.** Consolidar en un agente único crea un punto ciego: si todo se empuja por él, su muerte no dispara ninguna alerta — las series dejan de llegar, y un umbral sobre una serie ausente no alerta nada. Entonces Prometheus scrapea por pull todo lo que ya expone HTTP —incluido el propio agente— y el agente solo empuja lo que ningún pull alcanza: host, contenedores, base y logs.

**Rol de monitoreo propio en la base.** El exporter usa un rol de solo lectura con secret propio, no la credencial de la aplicación: el contenedor que tiene el socket de Docker y el stream de logs de todo el stack no debe portar una credencial de superusuario.

**Rotación de logs como default del daemon.** Un techo por contenedor —tamaño por archivo y cantidad de archivos— configurado en el daemon y no en cada servicio: así cubre todo contenedor presente y futuro sin repetir el bloque en cada módulo de compose. El techo se elige por la **ventana de recuperación ante un almacén de logs caído**, no por ahorrar disco: el agente relee de esos archivos, así que cuanto más chicos, menos historia se recupera. Nota de formato: ese archivo no admite comentarios y el daemon **rechaza cualquier clave desconocida y no arranca**, así que la justificación vive acá y el archivo solo lleva las dos opciones reales.

**Retención con dos techos.** Uno por tiempo y otro por tamaño. El segundo es el fusible: no depende de que la estimación de cardinalidad sea correcta, que es justamente lo que suele fallar. Riesgo aparte que la retención no cubre: un incidente de logging descontrolado puede generar en horas volúmenes muy por encima del peor escenario sostenido — eso se ataja con rotación a nivel del daemon de Docker, no con la retención del almacén.

**Métricas de capa de aplicación.** Ninguno de los colectores de infraestructura las captura. El mecanismo son las métricas nativas del reverse proxy —latencia y códigos de estado por router y servicio, cero contenedor nuevo y cero código de aplicación— más consultas sobre los logs de la aplicación. Un módulo dedicado daría un desglose más limpio por tipo de request, pero se difiere mientras no exista para la versión en uso: portarlo mete trabajo de código de aplicación, de alcance no acotado y con deuda de rebase permanente, en un repositorio que es puro-infra.

**Lo que queda sin cubrir, explícito:** el desglose de latencia por tipo de request y el conteo de long-polling. El proxy ve routers, no semántica de la aplicación. Y **Odoo devuelve 200 incluso ante errores de aplicación**, porque los envuelve en el payload JSON-RPC — así que la tasa de 5xx medida en el proxy detecta caídas del backend, no errores funcionales.

**Monitoreo de cron: decisión consciente de no sumar nada.** Se investigaron módulos pagos, heartbeats de la comunidad y queries propias en el exporter, y se concluyó que la cobertura actual alcanza. Un hallazgo pesó en la decisión: ni el hosting oficial gestionado expone tracking de fallo por job individual — solo consumo agregado por categoría. Se revisita si en la práctica un job falla en silencio y genera un problema real.

**Alerting nativo de Grafana**, no un componente separado: soporta consultas sobre métricas y sobre logs por igual, en el mismo lugar donde ya viven los dashboards, y cero contenedor nuevo. Sin esto, todo el stack de observabilidad sería pasivo — dashboards que hay que abrir a mano, contradiciendo el objetivo de detectar caídas rápido.

**Provisioning como código.** Datasources, dashboards y recursos de alerting se definen como archivos versionados junto al resto de la infraestructura. Resuelve el riesgo de perderlos si el contenedor se recrea, sin necesidad de un backup aparte. Consecuencia asumida: quedan de solo lectura en la UI, y un cambio se hace editando el archivo.

**Los umbrales de las alertas van literales, y no es un pendiente.** Grafana no ofrece mecanismo para parametrizarlos: el provisioning de alerting es YAML plano, sin la interpolación que sí tienen datasources y dashboards. Se probaron las dos formas contra la imagen del stack: `${VAR}` dentro de `params` ni siquiera parsea (`did not find expected ',' or ']'`, y la regla entera no se provisiona), y `"$__env{VAR}"` pasa como cadena literal a un campo que espera un número. Como el valor vive en el archivo de config de la herramienta, la regla del stack aplica sin excepción: si no se puede parametrizar por el mecanismo de esa herramienta, se versiona literal. El único umbral que se cruza con un valor de `.env` —el de «backup viejo» contra `RESTIC_MAX_AGE`— lo verifica `make observability-verify`.

---

## Secretos

**Mecanismo: `secrets:` nativo de Compose**, archivos montados, no variables de entorno. Una env var queda visible en texto plano vía `docker inspect` y `docker exec … env` — vector obvio para cualquiera que pueda ejecutar comandos en el contenedor. El mecanismo nativo evita ambos sin sumar dependencias.

Los valores viven como archivos planos en un directorio excluido de git, con permisos `640` y el grupo del GID que los consume. El `600` no sirve: Compose fuera de Swarm ignora `uid`/`gid`/`mode` para secrets de archivo, así que un `600` root-owned rompe la lectura de cualquier contenedor no-root.

**Descartado un secrets manager dedicado.** A esta escala sería sumar una pieza más corriendo, con su propio unsealing y su propio backup, para proteger algo que ya se protege razonablemente con archivos y permisos correctos.

**Una excepción, acotada y escrita:** la credencial de git con la que el servidor clona los módulos no es un secret de Compose. Al clonar en el host, **ningún contenedor la consume**, así que vive en el credential store del sistema. Es de solo lectura porque el servidor nunca escribe en un repo de addons.

**El backup de los secretos va aparte** del pipeline usado para el resto de los datos: si el servidor se pierde por completo, hace falta ese directorio para redesplegar. Respaldo manual y separado, no automatizado ni mezclado con los backups operativos.

---

## Gestión

**UI de gestión con privilegio sobre el socket de Docker: no. CLI y `Makefile` en su lugar.**

Una UI de ese tipo requiere el socket, que es privilegio equivalente a root sobre el host si el contenedor se compromete. Es superficie de ataque real, no "un contenedor más". Se evaluaron dos mitigaciones de red y ninguna elimina el riesgo de fondo: si la UI tiene hostname público para poder usarla como cualquier servicio web, su propio login queda como la única puerta. La visibilidad que daría ya está cubierta por el stack de observabilidad, y el proxy aporta su propio dashboard de ruteo.

Esto no prohíbe montar el socket `:ro` para descubrimiento u observación, que es un caso distinto: lo prohibido es una UI con privilegio sobre él.

**Actualizaciones automáticas: no.** Un upgrade de versión exige leer release notes y probar antes de aplicarse, ni siquiera en modo "solo notificar". La actualización es un acto deliberado del operador.

---

## Escaneo de vulnerabilidades

**A mano cuando el operador quiera mirar, sin target de `Makefile` ni script versionado.** Se construyó la versión automatizada, se probó contra el stack real, y no sobrevivió a la evidencia:

- **El resultado no cambia la acción.** Comparar dos tags consecutivos de la imagen oficial dio una reducción grande de hallazgos y **ninguno nuevo** — la conclusión fue adoptar, que era la conclusión *antes* de escanear. Un tag con fecha existe justamente para juntar parches de upstream, y sobre imágenes pineadas la única palanca es subir el tag. La asimetría es estructural: quedarse deja **más** CVEs conocidos, no menos, porque se acumulan contra una versión fija.
- **Donde sí hay decisión real, el escáner no manda.** En un salto de versión mayor la decisión la dominan compatibilidad, migración de esquema y port de los módulos. El delta de CVEs es una nota al pie.
- **Instalado no es alcanzable, y el escáner no puede saber la diferencia.** Es un inventariador con una base de datos: lee los paquetes instalados y los cruza contra un catálogo. No ejecuta nada ni conoce la configuración. Los hallazgos se concentran en el intérprete y la libc, presentes en toda imagen del planeta, o en herramientas de build que en el contenedor corriendo nunca procesan input de un atacante.
- **El contexto es lo que lo vuelve de bajo valor.** En un pipeline con varios servicios y varias personas commiteando, un escáner es genuinamente valioso: detecta lo que nadie miró. Con un operador, imágenes upstream pineadas y updates deliberados de a uno, casi todo lo que aporta ya lo aporta que el operador revise cada cambio.
- **Descartados también un gate por severidad y un archivo de excepciones.** Sin gate no hay nada que silenciar, y registrar la excepción para uno mismo es ceremonia, no revisión.

---

## Redes de Docker

**Tres redes por función:** `edge` (el túnel, el proxy y el almacén de métricas, que necesita alcanzarlos por pull), `app` (aplicación, pooler, base, backup, el proxy como puente y el agente de observabilidad, que entra a alcanzar la base) y `observability` (métricas, logs, dashboards y el agente).

Reduce el radio de impacto si un contenedor se compromete, con un mecanismo nativo de Compose y sin herramienta nueva. Dos consecuencias que un boceto ingenuo de tres redes no prevé: el almacén de métricas necesita membresía en `edge`, porque la topología híbrida lo obliga a scrapear el proxy y el túnel por pull directo; y el servicio de DNS local no está en ninguna red de Docker, porque corre en `network_mode: host`.

## Usuario en runtime

Contrapartida escrita del principio de correr como no-root: se registra quién no lo cumple y por qué, en vez de darlo por hecho.

| Servicio | Corre como | Por qué |
|---|---|---|
| DNS local | root | Bindea el `53`, puerto privilegiado, en `network_mode: host` |
| Base de datos | root → usuario propio | La imagen oficial arranca root y baja de usuario en su propio entrypoint |
| Aplicación | usuario propio | Cumple sin excepción |

---

## Modularización de Compose

`docker/compose.yaml` no es monolítico: declara los recursos compartidos —`networks:` y `secrets:`— y usa `include:` para sumar un módulo por capa.

- **Motivo:** un archivo por capa mantiene acotado el diff de cada cambio y hace auditable de un vistazo qué contenedores pertenecen a qué capa. Más fácil de revisar y de razonar sobre el radio de impacto que un archivo de cientos de líneas con todo mezclado.
- **Mecanismo:** `include:` en vez de encadenar `-f` a mano en cada invocación, lo que evita que una invocación se olvide un archivo y levante un subconjunto incompleto sin avisar.
- **Naming:** nunca `compose.override.yaml`. Ese nombre dispara el autoload especial de Compose —se aplica implícitamente sin pedirlo— y confunde la semántica: esto es modularización, con servicios distintos que no se solapan, no override de ambiente.

**Los entornos no productivos no son parte de esa cadena.** Staging es la misma cadena de módulos instanciada con otro nombre de proyecto más un archivo chico que pisa puertos y nombres; desarrollo es un módulo propio, standalone, sin túnel ni proxy ni backups. Los dos quedan deliberadamente **fuera del `include:` por defecto**: incluirlos por costumbre en una corrida de servidor arriesgaría exponer puertos de debug.
