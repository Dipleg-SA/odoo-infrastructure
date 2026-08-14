# Stacks: qué comparte cada uno y qué se decidió

Un **stack** acá es una combinación de tres cosas: un checkout del repositorio, un nombre de proyecto de Compose, y un conjunto de capas incluidas. Cambiar cualquiera de las tres da un stack distinto.

El repositorio implementa hoy **los tres**: cada uno tiene su entrypoint —`compose.yaml`, `compose.staging.yaml`, `compose.dev.yaml`— y nginx reemplazó a Traefik en el borde. La **Parte I** describe qué se comparte entre stacks y qué colisiona si se levanta un segundo. La **Parte II** recoge las decisiones tomadas para staging y development, y es lo que esos dos entrypoints implementan.

## Los tres stacks

|                    | Producción              | Staging                 | Development             |
|--------------------|-------------------------|-------------------------|-------------------------|
| Dónde corre        | Servidor                | Servidor                | Máquina del operador    |
| Checkout           | propio                  | propio                  | uno por feature         |
| Nombre de proyecto | `production`            | `staging`               | `development-<feature>` |
| Entrypoint         | `compose.yaml`          | `compose.staging.yaml`  | `compose.dev.yaml`      |
| Rama de addons     | default del Dockerfile  | `<versión>-stag`        | `feat/*`                |
| Proxy              | nginx con TLS           | nginx con TLS           | nginx sin TLS           |
| Túnel y certbot    | sí                      | sí                      | no                      |
| DNS local          | sí                      | no                      | no                      |
| Datos              | sí                      | sí                      | sí                      |
| Aplicación         | sí                      | sí                      | sí                      |
| Restore            | sí                      | sí                      | no                      |
| Backups            | sí                      | no                      | no                      |
| Observabilidad     | sí                      | no                      | no                      |
| Secrets            | 11                      | 8                       | 3, todos generados      |

La capa de backups es exclusiva de producción por decisión explícita, no por omisión: un segundo stack escribiría en la misma stanza de pgBackRest, el mismo repositorio de restic y los mismos archivos de estado del host, y su corrida apagaría la alerta de «backup viejo» del entorno real. La capa de restore, en cambio, **solo lee**, así que staging sí la lleva.

---

# Parte I — Qué comparten los tres

No todo se comparte del mismo modo. El nivel decide si dos stacks conviven o se pisan.

## 1. Archivos versionados — compartidos por definición

Todo lo que está en git es el mismo archivo para todo stack que salga de ese commit, tenga su propio directorio o no. Cambiarlo para uno lo cambia para todos.

Cada entorno tiene su **entrypoint** propio —un archivo raíz con su `include:`, sus `secrets:` y los ajustes que le hace a una capa compartida—, así que la columna dice qué capas y qué archivos de config alcanza cada uno.

| Archivo                                     | Producción     | Staging                     | Development                 |
|---------------------------------------------|----------------|-----------------------------|-----------------------------|
| entrypoint                                  | `compose.yaml` | `compose.staging.yaml`      | `compose.dev.yaml`          |
| plantilla de `.env`                         | `.env.prod.example` | `.env.stag.example`    | `.env.dev.example`          |
| `compose.proxy.yaml`                        | sí             | sí, sin publicar puertos    | sí, solo el 80 en loopback  |
| `compose.dns.yaml`                          | sí             | no                          | no                          |
| `compose.edge.yaml`                         | sí             | sí                          | no                          |
| `compose.db.yaml`                           | sí             | sí, sin archivar WAL        | sí, sin archivar WAL        |
| `compose.odoo.yaml`                         | sí             | sí, sin credencial SMTP     | sí, sin credencial SMTP     |
| `compose.restore.yaml`                      | sí             | sí                          | no                          |
| `compose.backups.yaml`                      | sí             | no                          | no                          |
| `compose.observability.yaml`                | sí             | no                          | no                          |
| `config/postgres/postgresql.conf`           | sí             | sí                          | sí                          |
| `config/pgbouncer/pgbouncer.ini`            | sí             | sí                          | sí                          |
| `config/odoo/odoo.conf`                     | sí             | sí                          | sí                          |
| `addons/addons.txt.example` (plantilla)     | sí             | sí                          | sí                          |
| `config/nginx/00-http` · `odoo.locations`   | sí             | sí                          | sí                          |
| `config/nginx/server-tls` · `server-plain`  | `-tls`         | `-tls`                      | `-plain`, fijado en su entrypoint |
| `config/certbot/wrapper.sh`                 | sí             | sí                          | no                          |
| `config/pgbackrest/pgbackrest.conf`         | sí             | sí, solo para restaurar     | no                          |
| `config/prometheus`                         | sí             | no                          | no                          |
| `config/loki`                               | sí             | no                          | no                          |
| `config/grafana`                            | sí             | no                          | no                          |
| `config/alloy`                              | sí             | no                          | no                          |
| `config/systemd/*`                          | sí             | no                          | no                          |
| `config/docker/daemon.json`                 | host, no stack | —                           | —                           |
| `docker/{odoo,postgres,dnsmasq}/`           | sí             | sí                          | sí                          |
| `scripts/verify.sh`                         | sí             | sí                          | sí                          |
| `scripts/addons.sh`                         | sí             | sí                          | sí                          |
| `scripts/backup.sh`                         | sí             | no                          | no                          |
| `scripts/failure-notify.sh`                 | sí             | no                          | no                          |
| `scripts/integrity-check.sh`                | sí             | sí                          | sí                          |
| `Makefile`                                  | sí             | sí                          | sí                          |

Cinco consecuencias que importan:

- **`scripts/failure-notify.sh` no lo llama nadie fuera de producción.** Su único invocador es el `OnFailure=` de las units de backup, que no se instalan en los otros stacks. Va donde va la capa de backups.
- **`scripts/integrity-check.sh` recorre el filestore por el contenedor de `odoo`.** Antes lo hacía por el de `backup`, que es exclusivo de producción, y eso lo dejaba fuera de staging — justo el entorno donde el simulacro de restore lo necesita. `odoo` monta el mismo volumen y lo lleva cualquier stack.
- **`config/odoo/odoo.conf` es único para los tres.** `workers`, `limit_memory_*` y `dbfilter` son los mismos en la máquina del operador que en el servidor. Un stack de desarrollo que quiera menos workers necesita otro mecanismo, no otra copia del archivo — los principios prohíben archivos `.example` paralelos a un config.
- **Las plantillas de `.env` son tres, y eso son tres copias.** La alternativa era un archivo genérico del que cada entorno borra los bloques que no le tocan, y borrar sale mal más seguido que completar: `cp .env.stag.example .env` deja el `COMPOSE_FILE`, el `PG_ARCHIVE_MODE=off` y las claves de staging ya puestas, sin decidir nada. La copia se paga con un chequeo y no con disciplina — `make test` resuelve cada entrypoint con su plantilla y falla si queda una variable sin declarar, que es justo lo que pasa cuando una clave nueva entra a una capa compartida y se suma a una sola plantilla.
- **`dbfilter = ^odoo$` y el rol `odoo` son fijos.** No es un problema mientras cada stack tenga su propio volumen `pgdata`, que es lo que pasa: el nombre de la base se repite, la base no.

## 2. Estado del host no versionado — compartido por checkout

Vive fuera de git pero dentro del directorio del repositorio. **Esta tabla es la razón por la que cada entorno lleva su propio checkout** (Parte II): compartir uno solo significaría compartir todo lo de abajo.

| Ruta                                      | Qué es                                     | Riesgo si se comparte                                                                          |
|-------------------------------------------|--------------------------------------------|------------------------------------------------------------------------------------------------|
| `.env`                                    | Valores por deployment                     | Un solo `PUBLIC_HOSTNAME`, un solo `COMPOSE_PROJECT_NAME`, un solo `PG_ARCHIVE_MODE` para los dos |
| `secrets/*`                               | Credenciales — 11 en producción, 8 en staging, 3 en development | Staging usaría las credenciales reales de Cloudflare y SMTP                  |
| `state/textfile/`                         | Métricas de backup y de vencimiento del certificado | Un stack pisa las métricas del otro                                                     |
| `state/meta/addons.txt`                   | Registro de addons del snapshot            | Ídem                                                                                             |
| `addons/addons.txt`                       | El manifiesto real — a diferencia de su plantilla, no viaja versionado: difiere de contenido entre los tres, no solo de rama | Un módulo en adaptación en development se filtraría a producción |
| `addons/.repos/*.git` y el contenido de `addons/<categoría>/` | Clon bare y worktrees, **un árbol por checkout** — la plantilla y el `.gitkeep` de cada categoría son la excepción versionada de esa misma carpeta | Dos entornos materializando ramas distintas sobre el mismo árbol |

El estado de los certificados **no está en esta tabla**: vive en un volumen nombrado que escribe certbot, con alcance de proyecto, así que cae en el nivel 3 y no se comparte. Es lo que hace que cambiar de checkout no lo toque.

El árbol de addons dejó de tener nivel de entorno adentro: la estructura de tres worktrees existía para separar lo que ahora separa el directorio del checkout, y superponer dos aislamientos dejaba uno que no aislaba nada.

## 3. Recursos de Docker con alcance de proyecto — no compartidos

Compose les antepone el nombre del proyecto, así que dos stacks con nombres distintos no se tocan. Esto ya está resuelto en el repositorio.

- **Contenedores.** Los catorce declaran `container_name: ${COMPOSE_PROJECT_NAME}-<servicio>` — once que levanta `make up`, más `certbot` y los dos de `restore`, que viven detrás de un `profiles:`. El nombre es global al daemon: sin esa derivación, un segundo stack no arranca.
- **Volúmenes.** `pgdata`, `odoo-data`, `prometheus-data`, `loki-data`, `grafana-data` se materializan como `<proyecto>_<nombre>`.
- **Redes.** `edge`, `app`, `observability` → `<proyecto>_<red>`.
- **Hostnames de `backup` y `alloy`.** Derivados del proyecto: restic agrupa la retención por `(host, paths)` y Alloy etiqueta cada métrica con `instance`. Fijos, dos stacks caerían en el mismo grupo de retención y emitirían series idénticas.
- **Tags de imagen.** `local/<servicio>:${COMPOSE_PROJECT_NAME}` (ver [Imágenes](#imágenes)). El nombre de una imagen es global al daemon: con un tag fijo, el `build` de un stack pisaba la imagen que corre el otro sin fallar ni avisar.

El nombre de proyecto tiene tres fuentes, en orden de precedencia: la variable `COMPOSE_PROJECT_NAME` del entorno, el `name:` del archivo, y —si no hay ninguno de los dos— **el nombre del directorio**. Verificado, incluida la interpolación de `${COMPOSE_PROJECT_NAME}` a partir de cualquiera de las tres. Ningún `compose.*.yaml` declara `name:`: el nombre se declara en `.env`, y cambiarlo renombra también volúmenes, imágenes y el grupo de retención de restic, así que **no es una edición, es una migración**.

## 4. Recursos globales al host o al daemon — compartidos siempre

Acá está lo que **no** resuelve el nombre de proyecto.

| Recurso                                                                | Quién lo toma               | Qué pasa con un segundo stack                                                                                                                                                                                       |
|------------------------------------------------------------------------|-----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `${LOCAL_IP}:80` y `:443`                                              | nginx de producción         | Resuelto por exclusión: staging borra su `ports:` entero y entra por el túnel; development publica en loopback y otro puerto                                                                                            |
| `127.0.0.1:3000`                                                       | Grafana                     | El segundo no puede bindear — resuelto por exclusión: la capa es solo de producción                                                                                                                                    |
| `:53` en `network_mode: host`                                          | dnsmasq                     | Ídem, y sin salida: es el único servicio que no admite un segundo de ninguna forma                                                                                                                                     |
| `--name odoo-oneoff`                                                   | `make odoo-install/update`  | Dos one-off simultáneos en el mismo host fallan. Falla ruidoso y está documentado                                                                                                                                      |
| Units `odoo-backup-*` y `odoo-cert-renew.*`                            | systemd                     | Nombres fijos con `WorkingDirectory` absoluto: apuntan a un checkout, no a un stack. **Staging también renueva certificados**, así que instala su copia con otro nombre o pisa la de producción                          |
| Repositorio de restic y stanza de pgBackRest                           | Capa de backups             | Resuelto por exclusión para la escritura: solo producción archiva y respalda. Los otros stacks **leen** la misma stanza para restaurar, y eso es seguro solo mientras `PG_ARCHIVE_MODE=off` los mantenga sin archivar    |

El proxy ya no aparece por descubrimiento. Con Traefik, el provider de Docker leía el daemon entero y cada instancia encontraba **también** el `odoo` del otro stack, con los mismos nombres de router; había que derivarlos del proyecto para que no se pisaran. nginx sirve lo que dice su archivo y el problema desapareció con la herramienta.

## Lo que ve la observabilidad de producción

Vale distinguirlo porque no es simétrico:

- **Los jobs de scrape de Prometheus apuntan a nombres de servicio** (`alloy:12345`, …). Se resuelven dentro de las redes del proyecto, así que **un segundo stack es invisible** para ellos. La latencia y la tasa de error de la aplicación salen del access log de nginx en JSON, consultado desde Loki, y son igual de propias del proyecto.
- **Alloy monta el socket de Docker y `/rootfs`.** Su cAdvisor enumera *todos* los contenedores del host, así que **las métricas de contenedor de staging sí aparecen** en el Prometheus de producción, etiquetadas con el `instance` de producción.

O sea: staging queda medio observado por accidente. Métricas de contenedor sí, disponibilidad de servicios no.

---

# Parte II — Por qué está armado así

Lo que la Parte I describe, con el porqué de cada elección y lo que se descartó. Está implementado: acá vive el razonamiento, no el plan.

## Topología

Tres tipos de checkout en directorios separados: **producción** y **staging** en el servidor, **n × development** en la máquina del operador, con **uno solo corriendo por vez**. Cada checkout trae su propio `.env`, `secrets/`, `state/` y árbol de addons.

El aislamiento por directorio se eligió sobre un checkout compartido porque toda la tabla del nivel 2 deja de ser un riesgo: un error en staging no puede alcanzar las credenciales ni el `state/` de producción, y no depende de que nadie se equivoque de terminal.

**El nombre del stack se declara en `.env`, al lado de `COMPOSE_FILE`. Sin excepciones.** Ningún `compose.*.yaml` declara `name:`: la identidad de un stack sale del mismo archivo que dice qué capas incluye, en los tres entornos y con un solo mecanismo que aprender.

```
/srv/odoo-production            COMPOSE_PROJECT_NAME=production
/srv/odoo-staging               COMPOSE_PROJECT_NAME=staging
~/odoo-development-sale         COMPOSE_PROJECT_NAME=development-sale
~/odoo-development-accountant   COMPOSE_PROJECT_NAME=development-accountant
```

El modo de falla está medido y es benigno: si la variable falta o queda vacía, Compose cae al **nombre del directorio**, que ya es único por checkout. Olvidarla no produce un volumen compartido, produce un nombre más feo. El único caso peligroso es copiar un `.env` de un checkout a otro, y contra eso no hay mecanismo que ayude.

Se descartó declarar `name:` en cada entrypoint. Con un literal compartido entre dos checkouts de development, los dos resuelven al **mismo** volumen `development_pgdata`: no colisionan al arrancar, porque corre uno a la vez, se pisan los datos en silencio — precisamente lo que un entorno por feature viene a evitar.

Renombrar el proyecto renombra sus volúmenes, y Docker no sabe renombrar un volumen: en un stack ya corriendo se copian `pgdata` y `odoo-data` con todo abajo, y los tres de observabilidad se dejan nacer vacíos, porque son datos de diagnóstico y no de restauración. En un deploy nuevo no cuesta nada, que es el caso de este repositorio.

## Composición

Un **entrypoint por entorno**: un archivo raíz con su propio `include:`, y el `.env` de cada checkout eligiendo cuál con `COMPOSE_FILE`. Verificado: `docker compose` respeta `COMPOSE_FILE` y `COMPOSE_PROJECT_NAME` desde `.env` sin ningún flag, así que **ningún target del Makefile cambia por esto**.

| Entrypoint             | Capas que incluye                                            | Secrets |
|------------------------|--------------------------------------------------------------|---------|
| `compose.yaml`         | dns, proxy, borde, datos, aplicación, backups, restore, observabilidad | 11 |
| `compose.staging.yaml` | proxy, borde, datos, aplicación, restore                     | 8       |
| `compose.dev.yaml`     | proxy, datos, aplicación                                     | 3       |

Cada entrypoint declara **solo los secrets que sus capas usan**. Compose falla al arrancar si un `file:` declarado no existe, así que declarar los once en dev obligaría a fabricar ocho archivos inertes. Los tres de development son de los que `secrets-init.sh` genera con `openssl`: **cero trabajo manual por checkout**.

Se eligió el entrypoint por entorno sobre un módulo de override porque **Compose no sabe quitar un servicio ya incluido** — staging tendría que cargar la capa de backups para desactivarla.

Tres capas salieron por extracción de archivos que ya existían:

- **`compose.proxy.yaml`** — nginx, los tres entornos. Sale de `compose.edge.yaml` porque development quiere el proxy —para que `proxy_mode` no mienta— pero no el túnel ni los certificados. Lo que queda en `compose.edge.yaml` es `cloudflared` y `certbot`.
- **`compose.dns.yaml`** — dnsmasq, solo producción. Sale de `compose.edge.yaml` porque el `:53` en `network_mode: host` no se puede duplicar y staging no necesita sobrevivir a una caída de internet.
- **`compose.restore.yaml`** — `restore-db` y `restore-files`, producción y staging. Sale de `compose.backups.yaml`: esos dos servicios solo leen del repositorio remoto, así que llevarlos a staging no rompe la regla de que la capa de backups es exclusiva de producción.

Staging no publica ningún puerto — `ports: !reset []`, verificado en Compose v5.1.4: borra el bloque entero de un servicio traído por `include:`, sin tocar el archivo compartido ni parametrizar nada. No lo necesita: `cloudflared` alcanza al proxy **por la red `edge`, por nombre de contenedor**, no por puertos publicados.

## Borde: nginx en los tres entornos

Reemplaza a Traefik. Producción y staging con TLS y hostname propio; development sin TLS, publicando en loopback.

Lo que decide el cambio:

- **Uniformidad.** Development tiene un proxy real escribiendo `X-Forwarded-*`, así que `proxy_mode = True` deja de mentir en algún entorno. La alternativa era publicar el `8069` de Odoo directo en dev, con esa incoherencia adentro.
- **Sin socket de Docker.** Desaparece el descubrimiento cruzado entre stacks: cada nginx sirve lo que dice su archivo. Con Traefik hacía falta derivar los nombres de router del proyecto para que dos stacks no se pisaran.

Lo que cuesta, asumido a conciencia: ACME deja de ser gratis (ver abajo) y las métricas de capa de aplicación hay que reconstruirlas.

Detalles que van desde el primer día, no cuando aparezca el síntoma:

- **`resolver 127.0.0.11 valid=10s` y `proxy_pass` a través de una variable.** nginx resuelve los upstream al arrancar y cachea; si Odoo se recrea y cambia de IP, devuelve 502 hasta que lo recargues. Traefik no tenía este problema porque escucha eventos de Docker.
- `limit_req` para POST `/web/login`, `location /websocket` al `8072`, el resto al `8069`.
- Config por entorno con las plantillas `envsubst` de la imagen oficial: `nginx.conf` es un archivo versionado y el hostname varía por deployment.
- Publicación: producción `${LOCAL_IP}:80` y `:443` para la LAN, staging nada, development un puerto de loopback.

## Certificados

`certbot/dns-cloudflare` con DNS-01, disparado por timer de systemd, en producción y staging.

- **Credenciales desde archivo** (`--dns-cloudflare-credentials`), no por variable de entorno: encaja con el modelo de secrets sin excepciones. `acme.sh` quedó descartado por tomar el token por env.
- **Hereda el `OnFailure=`** que ya existe para los backups. El modo de falla que importa no es que la emisión salga mal el primer día —eso se ve— sino que la renovación número cuatro falle en silencio y el certificado venza sesenta días después.
- **DNS-01 y no HTTP-01** para que la emisión no dependa del ingreso: hoy el certificado se emite aunque el borde esté roto.

## Imágenes

`local/<servicio>:${COMPOSE_PROJECT_NAME}`. `restore-db` sigue el mismo tag — si no, un restore usaría una imagen distinta a la que escribió el `pgdata`.

Se descartó derivar el tag de la versión de Odoo: la imagen **no** es función de la versión. También la definen el `Dockerfile`, el `entrypoint.sh` y `requirements.txt`, que pueden diferir entre dos checkouts parados en commits distintos — o sea que volvería a colisionar justo en el caso para el que se la habría elegido.

## Addons

**Un árbol por checkout**: `addons/<categoría>/<repo>`, sin nivel de entorno. La estructura de tres worktrees existía para separar lo que ahora separa el directorio del checkout; mantenerla era superponer dos mecanismos de aislamiento, y el de adentro ya no aislaba. `addons.sh` perdió `entornos()`, `ensure_dev_worktree()` y el bootstrap de la rama `-stag`.

`ODOO_BRANCH` se partió en dos, porque cumplía dos funciones a la vez:

- **La versión de Odoo** vive solo en el `FROM` del Dockerfile, que es quien la consume. Salió de `.env`.
- **`ADDONS_BRANCH`** dice la rama de los repos de addons en este checkout. Su default se lee del Dockerfile, así que producción no declara nada y solo staging pone `<versión>-stag`.

El chequeo de `verify.sh` pasó de igualdad a prefijo: acepta `19.0` y `19.0-stag`, rechaza `18.0` contra imagen `19.0`. Conserva lo que protegía —clonar ramas de una versión y montarlas en un Odoo de otra— sin castigar el sufijo de entorno. Una rama de feature no declara versión en el nombre, así que ahí **avisa en vez de fallar**: es lo único que se puede afirmar de `feat/*`, y un rojo permanente en cada checkout de desarrollo enseña a ignorar la salida entera.

## Datos de staging

Restore desde el repositorio remoto, de solo lectura. El propósito es doble y deliberado: **sembrar staging y hacer el simulacro de restore son la misma operación**. Los principios exigen simulacro periódico, y ese es el paso que siempre se posterga porque no tiene ocasión natural; atarlo a «refrescar staging» se la da.

Staging queda con datos reales de clientes, **y sin credenciales SMTP**. Un `-u` que dispare correo, o una tarea programada que venía en la base restaurada, mandaría mail de verdad a clientes de verdad desde el entorno que existe para romper cosas. Sin el secret, Odoo encola y falla al enviar: visible adentro, inofensivo afuera. Su entrypoint además vacía `SMTP_HOST`, porque si dependiera solo de `.env` un archivo copiado de producción alcanzaría para mandar.

Y **no archiva WAL**. Apunta a la stanza de producción para poder restaurar, así que con `archive_mode` prendido le empujaría su propio WAL al repositorio del entorno real. Lo decide `PG_ARCHIVE_MODE` en el `-c` de `compose.db.yaml` y no `postgresql.conf`, que es el mismo archivo para los tres; `make verify-db` exige el valor que corresponde a las capas del stack, no uno fijo.

La anonimización se evaluó y se descartó por ahora: es un script que envejece mal, porque protege exactamente los campos que conocía el día que se escribió. Deja de ser opcional si alguna vez entra a staging alguien más que el operador.

## Observabilidad

Solo producción. La latencia y la tasa de error de la capa de aplicación salen del **access log de nginx en JSON** (`$request_time`, `$status`, `$uri`), consultado desde Loki — sin componentes nuevos, porque Alloy ya manda esos logs.

Se descartó un exporter que parsee el log a métricas de Prometheus: es técnicamente mejor y no justifica un contenedor más. `stub_status` no alcanza — da conexiones y un contador de requests, sin latencia ni desglose por código.

**Al migrar, las alertas primero.** Una alerta mal migrada no falla ruidosa: simplemente no dispara nunca. Las dos que dependían de Traefik se rehicieron — la tasa de error a LogQL sobre el access log, y el vencimiento del certificado a una métrica que `cert.sh` escribe en `state/textfile/` por el mismo mecanismo que ya usaba `backup.sh`.

Esa métrica mide **lo que certbot tiene en disco, no lo que nginx sirve**. El caso «renovó y nadie recargó» lo cubren el reload del propio script y el chequeo de `verify-odoo` contra el socket real, que es el único que abre una conexión TLS de verdad.

## Tooling

Los targets exclusivos de una capa llevan guarda, y la guarda le pregunta **a la composición**, no a una variable declarada:

```make
require-backups:
	@docker compose config --services 2>/dev/null | grep -qx backup || \
	  { echo "este stack no incluye la capa de backups — es exclusiva de producción" >&2; exit 2; }
```

Son dos y no una, porque las capas son distintas: `require-backups` cuelga de `backup`, `backup-full` y `backup-check`; `require-restore` de `restore-up` y `restore-down`. Staging **sí** restaura, así que una guarda sola le prohibiría justo lo que tiene que hacer. Una variable `STACK=` sería una tercera declaración de algo que los entrypoints ya dicen, y divergiría el día que aparezca un cuarto entorno.

**`verify.sh` sí necesitó cambios, y más de los previstos.** Omitir lo que no está corriendo no alcanzaba: un servicio caído y una capa que este entorno no lleva se veían igual, y la segunda salía en rojo. Ahora le pregunta a la composición —`declarado`, `bind_declarado`, `modo_plain`— y omite capas enteras, puertos que este stack no publica y los chequeos de TLS de un proxy en texto plano. El principio que quedó: **el verificador deriva de la composición todo lo que la composición ya sabe**, en vez de repetir en su código la cadena de defaults del `.env`.

---

# Parte III — Pendientes

**El resolver de la LAN no lo decide este repositorio.** `dnsmasq` resuelve el hostname para quien le pregunte, pero quién le pregunta lo reparte el DHCP del router. El chequeo que parecía cubrirlo usaba `dig … @servidor`, que prueba que dnsmasq contesta y no que alguien lo use: hoy es un prerrequisito escrito de `INSTALL.md`, un `dig` sin `@` desde un equipo de la LAN, y un `omitir` explícito en `verify.sh` que dice que desde el servidor no se puede verificar. **Sigue sin haber mecanismo**, porque no hay ninguno del lado del stack — lo que hay es que dejó de dar verde por accidente.

**El workflow de CI sigue sin poder existir.** Hay 105 chequeos de `make test` más `bash -n` y shellcheck listos para correr en cada push, y ningún lugar donde correrlos: esta rama no tiene remoto propio, y el `origin` actual guarda la identidad del deployment que la rama elimina. Es una decisión pendiente sobre dónde vive el repositorio, no trabajo técnico pendiente.

Los otros tres arrastres se cerraron:

- **Imágenes al día.** `alpine` 3.20 → 3.24, Odoo `19.0-20260630` → `19.0-20260810`, nginx `1.29.3` → `1.31.3` (misma rama mainline), Grafana 13.1.2 → 13.1.3, cloudflared 2026.7.2 → 2026.8.0 y certbot 5.1.0 → 5.7.0. Postgres 17.10, PgBouncer, restic, Prometheus, Loki y Alloy ya estaban en su último tag estable.
- **`pgbackrest.conf` se quedó sin sección de stanza.** El nombre, `pg1-path` y `pg1-user` llegan por `PGBACKREST_*` desde `compose.db.yaml` y `compose.restore.yaml`, junto al `POSTGRES_USER` del que `pg1-user` tiene que ser copia. La invariante «el `[nombre]` del archivo tiene que coincidir con el `.env`» desapareció: ya no hay dos lados que puedan divergir. `verify-db` dejó de comparar cadenas y ahora lee el valor efectivo dentro del contenedor (`pgbackrest help archive-push pg1-path`).
- **Los umbrales de Grafana quedan literales**, porque no hay mecanismo: el provisioning de alerting no interpola nada. El detalle de lo que se probó está en `docs/architecture.md`.
