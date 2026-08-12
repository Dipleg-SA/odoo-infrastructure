# Stacks: qué comparte cada uno y qué se decidió

Un **stack** acá es una combinación de tres cosas: un checkout del repositorio, un nombre de proyecto de Compose, y un conjunto de capas incluidas. Cambiar cualquiera de las tres da un stack distinto.

El repositorio implementa hoy **uno solo**: producción, con Traefik en el borde y un árbol de addons pensado para tres entornos dentro de un mismo checkout. La **Parte I** describe ese estado y qué colisiona si se levanta un segundo stack. La **Parte II** recoge las decisiones tomadas para staging y development — varias de ellas reemplazan lo que hay hoy. Nada de la Parte II está implementado todavía.

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

# Parte I — Cómo está el repositorio hoy

No todo se comparte del mismo modo. El nivel decide si dos stacks conviven o se pisan.

## 1. Archivos versionados — compartidos por definición

Todo lo que está en git es el mismo archivo para todo stack que salga de ese commit, tenga su propio directorio o no. Cambiarlo para uno lo cambia para todos.

| Archivo                                     | Producción     | Staging                     | Development                 |
|---------------------------------------------|----------------|-----------------------------|-----------------------------|
| `compose.yaml` (redes, secrets, `include:`) | sí             | sí, con otro `include:`     | sí, con otro `include:`     |
| `compose.edge.yaml`                         | sí             | sí                          | no                          |
| `compose.db.yaml`                           | sí             | sí                          | sí                          |
| `compose.odoo.yaml`                         | sí             | sí, con otro bind de addons | sí, con otro bind de addons |
| `compose.backups.yaml`                      | sí             | no                          | no                          |
| `compose.observability.yaml`                | sí             | no                          | no                          |
| `config/postgres/postgresql.conf`           | sí             | sí                          | sí                          |
| `config/pgbouncer/pgbouncer.ini`            | sí             | sí                          | sí                          |
| `config/odoo/odoo.conf`                     | sí             | sí                          | sí                          |
| `config/odoo/addons.txt` (manifiesto)       | sí             | sí                          | sí                          |
| `config/traefik/traefik.yaml`               | sí             | sí                          | no                          |
| `config/pgbackrest/pgbackrest.conf`         | sí             | no                          | no                          |
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
| `scripts/integrity-check.sh`                | sí             | hoy no puede                | hoy no puede                |
| `Makefile`                                  | sí             | sí                          | sí                          |

Cuatro consecuencias que importan:

- **`scripts/failure-notify.sh` no lo llama nadie fuera de producción.** Su único invocador es el `OnFailure=` de las units de backup, que no se instalan en los otros stacks. Va donde va la capa de backups.
- **`scripts/integrity-check.sh` es deseable en staging y hoy no corre ahí.** Hace `docker compose exec -T backup` para recorrer el filestore, y el servicio `backup` es exclusivo de producción. Es justo el chequeo que quiere un simulacro de restore, así que o se le da otro contenedor con el volumen montado, o staging se queda sin verificar sus adjuntos.
- **`config/odoo/odoo.conf` es único para los tres.** `workers`, `limit_memory_*` y `dbfilter` son los mismos en la máquina del operador que en el servidor. Un stack de desarrollo que quiera menos workers necesita otro mecanismo, no otra copia del archivo — los principios prohíben archivos `.example` paralelos.
- **`dbfilter = ^odoo$` y el rol `odoo` son fijos.** No es un problema mientras cada stack tenga su propio volumen `pgdata`, que es lo que pasa: el nombre de la base se repite, la base no.

## 2. Estado del host no versionado — compartido por checkout

Vive fuera de git pero dentro del directorio del repositorio. **Esta tabla es la razón por la que cada entorno lleva su propio checkout** (Parte II): compartir uno solo significaría compartir todo lo de abajo.

| Ruta                                      | Qué es                                     | Riesgo si se comparte                                                                          |
|-------------------------------------------|--------------------------------------------|------------------------------------------------------------------------------------------------|
| `.env`                                    | Valores por deployment                     | Un solo `PUBLIC_HOSTNAME`, un solo `LOCAL_IP`, un solo `PGBACKREST_STANZA` para los dos stacks   |
| `secrets/*` (11 archivos)                 | Credenciales                               | Staging usaría las credenciales reales de R2, Cloudflare y SMTP                                  |
| `config/traefik/acme.json`                | Estado del resolver ACME                   | Dos Traefik escribiendo el mismo archivo                                                         |
| `state/textfile/`                         | Métricas de backup que lee Alloy           | Un stack pisa las métricas del otro                                                              |
| `state/meta/addons.txt`                   | Registro de addons del snapshot            | Ídem                                                                                             |
| `addons/.repos/*.git`                     | Clon bare compartido por los tres árboles  | Ninguno: es el diseño de hoy, un bare y tres worktrees                                           |
| `addons/{production,staging,development}` | Los tres worktrees                         | Ninguno: uno por entorno                                                                         |

El árbol de addons es la única parte de este nivel pensada para compartirse — y es justamente la que la Parte II simplifica, porque con checkouts separados ya no separa nada.

## 3. Recursos de Docker con alcance de proyecto — no compartidos

Compose les antepone el nombre del proyecto, así que dos stacks con nombres distintos no se tocan. Esto ya está resuelto en el repositorio.

- **Contenedores.** Los trece declaran `container_name: ${COMPOSE_PROJECT_NAME}-<servicio>`. El nombre es global al daemon: sin esa derivación, un segundo stack no arranca.
- **Volúmenes.** `pgdata`, `odoo-data`, `prometheus-data`, `loki-data`, `grafana-data` se materializan como `<proyecto>_<nombre>`.
- **Redes.** `edge`, `app`, `observability` → `<proyecto>_<red>`.
- **Hostnames de `backup` y `alloy`.** Derivados del proyecto: restic agrupa la retención por `(host, paths)` y Alloy etiqueta cada métrica con `instance`. Fijos, dos stacks caerían en el mismo grupo de retención y emitirían series idénticas.
- **Tags de imagen.** `local/<servicio>:${COMPOSE_PROJECT_NAME}` (ver [Imágenes](#imágenes)). El nombre de una imagen es global al daemon: con un tag fijo, el `build` de un stack pisaba la imagen que corre el otro sin fallar ni avisar.

El nombre de proyecto tiene tres fuentes, en orden de precedencia: la variable `COMPOSE_PROJECT_NAME` del entorno, el `name:` del archivo, y —si no hay ninguno de los dos— **el nombre del directorio**. Verificado, incluida la interpolación de `${COMPOSE_PROJECT_NAME}` a partir de cualquiera de las tres. Ningún `compose.*.yaml` declara `name:`: el nombre se declara en `.env`, y cambiarlo renombra también volúmenes, imágenes y el grupo de retención de restic, así que **no es una edición, es una migración**.

## 4. Recursos globales al host o al daemon — compartidos siempre

Acá está lo que **no** resuelve el nombre de proyecto.

| Recurso                                                                | Quién lo toma               | Qué pasa con un segundo stack                                                                                                                                                                                       |
|------------------------------------------------------------------------|-----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `${LOCAL_IP}:80` y `:443`                                              | Traefik                     | El segundo proxy no puede bindear                                                                                                                                                                                      |
| `127.0.0.1:8080`                                                       | Dashboard de Traefik        | Ídem                                                                                                                                                                                                                   |
| `127.0.0.1:3000`                                                       | Grafana                     | Ídem                                                                                                                                                                                                                   |
| `:53` en `network_mode: host`                                          | dnsmasq                     | Ídem, y sin salida: es el único servicio que no admite un segundo de ninguna forma                                                                                                                                     |
| Nombres de routers de Traefik (`odoo`, `odoo-ws`, `odoo-login`)        | Etiquetas del servicio odoo | El provider de Docker no está acotado al proyecto: lee el daemon entero. Cada Traefik descubre **también** el odoo del otro stack, con los mismos nombres de router. `exposedByDefault: false` no filtra: los dos traen `traefik.enable=true` |
| `--name odoo-oneoff`                                                   | `make odoo-install/update`  | Dos one-off simultáneos en el mismo host fallan. Falla ruidoso y está documentado                                                                                                                                      |
| Units `odoo-backup-*`                                                  | systemd                     | Nombres fijos con `WorkingDirectory` absoluto: apuntan a un checkout, no a un stack                                                                                                                                    |
| Repositorio de restic y stanza de pgBackRest                           | Capa de backups             | Resuelto por exclusión: staging no la incluye                                                                                                                                                                          |

## Lo que ve la observabilidad de producción

Vale distinguirlo porque no es simétrico:

- **Los jobs de scrape de Prometheus apuntan a nombres de servicio** (`alloy:12345`, `traefik:8080`, …). Se resuelven dentro de las redes del proyecto, así que **un segundo stack es invisible** para ellos.
- **Alloy monta el socket de Docker y `/rootfs`.** Su cAdvisor enumera *todos* los contenedores del host, así que **las métricas de contenedor de staging sí aparecen** en el Prometheus de producción, etiquetadas con el `instance` de producción.

O sea: staging queda medio observado por accidente. Métricas de contenedor sí, disponibilidad de servicios no.

---

# Parte II — Decisiones

Nada de esto está implementado. Es el destino acordado, con el porqué de cada elección.

## Topología

Tres tipos de checkout en directorios separados: **producción** y **staging** en el servidor, **n × development** en la máquina del operador, con **uno solo corriendo por vez**. Cada checkout trae su propio `.env`, `secrets/`, `state/` y árbol de addons.

El aislamiento por directorio se eligió sobre un checkout compartido porque toda la tabla del nivel 2 deja de ser un riesgo: un error en staging no puede alcanzar las credenciales, el `acme.json` ni el `state/` de producción, y no depende de que nadie se equivoque de terminal.

**El nombre del stack se declara en `.env`, al lado de `COMPOSE_FILE`. Sin excepciones.** Ningún `compose.*.yaml` declara `name:`: la identidad de un stack sale del mismo archivo que dice qué capas incluye, en los tres entornos y con un solo mecanismo que aprender.

```
/srv/odoo-production            COMPOSE_PROJECT_NAME=production
/srv/odoo-staging               COMPOSE_PROJECT_NAME=staging
~/odoo-development-sale         COMPOSE_PROJECT_NAME=development-sale
~/odoo-development-accountant   COMPOSE_PROJECT_NAME=development-accountant
```

El modo de falla está medido y es benigno: si la variable falta o queda vacía, Compose cae al **nombre del directorio**, que ya es único por checkout. Olvidarla no produce un volumen compartido, produce un nombre más feo. El único caso peligroso es copiar un `.env` de un checkout a otro, y contra eso no hay mecanismo que ayude.

Se descartó declarar `name:` en cada entrypoint. Con un literal compartido entre dos checkouts de development, los dos resuelven al **mismo** volumen `development_pgdata`: no colisionan al arrancar, porque corre uno a la vez, se pisan los datos en silencio — precisamente lo que un entorno por feature viene a evitar.

Renombrar el proyecto de producción renombra sus volúmenes, y Docker no sabe renombrar un volumen. Si la adopción de esta estructura pasa por un redeploy con restore, nacen con el nombre nuevo y no hay migración; si se renombra sobre un stack ya corriendo, se copian `pgdata` y `odoo-data` con el stack abajo, y los tres de observabilidad se dejan nacer vacíos.

## Composición

Un **entrypoint por entorno**: un archivo raíz con su propio `include:`, y el `.env` de cada checkout eligiendo cuál con `COMPOSE_FILE`. Verificado: `docker compose` respeta `COMPOSE_FILE` y `COMPOSE_PROJECT_NAME` desde `.env` sin ningún flag, así que **ningún target del Makefile cambia por esto**.

| Entrypoint             | Capas que incluye                                            | Secrets |
|------------------------|--------------------------------------------------------------|---------|
| `compose.yaml`         | dns, proxy, borde, datos, aplicación, backups, restore, observabilidad | 11 |
| `compose.staging.yaml` | proxy, borde, datos, aplicación, restore                     | 8       |
| `compose.dev.yaml`     | proxy, datos, aplicación                                     | 3       |

Cada entrypoint declara **solo los secrets que sus capas usan**. Compose falla al arrancar si un `file:` declarado no existe, así que declarar los once en dev obligaría a fabricar ocho archivos inertes. Los tres de development son de los que `secrets-init.sh` genera con `openssl`: **cero trabajo manual por checkout**.

Se eligió el entrypoint por entorno sobre un módulo de override porque **Compose no sabe quitar un servicio ya incluido** — staging tendría que cargar la capa de backups para desactivarla.

Tres capas nuevas, todas por extracción de archivos existentes:

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

**Un árbol por checkout**: `addons/<categoría>/<repo>`, sin nivel de entorno. La estructura de tres worktrees existía para separar lo que ahora separa el directorio del checkout; mantenerla sería superponer dos mecanismos de aislamiento, y el de adentro ya no aísla. `addons.sh` pierde `entornos()`, `ensure_dev_worktree()` y el bootstrap de la rama `-stag`.

`ODOO_BRANCH` se parte en dos, porque hoy cumple dos funciones a la vez:

- **La versión de Odoo** vive solo en el `FROM` del Dockerfile, que es quien la consume. Deja de estar en `.env`.
- **`ADDONS_BRANCH`** dice la rama de los repos de addons en este checkout. Su default se lee del Dockerfile, así que producción no declara nada y solo staging pone `<versión>-stag`.

El chequeo de `verify.sh` pasa de igualdad a prefijo: acepta `19.0` y `19.0-stag`, rechaza `18.0` contra imagen `19.0`. Conserva lo que protegía —clonar ramas de una versión y montarlas en un Odoo de otra— sin castigar el sufijo de entorno.

## Datos de staging

Restore desde el repositorio remoto, de solo lectura. El propósito es doble y deliberado: **sembrar staging y hacer el simulacro de restore son la misma operación**. Los principios exigen simulacro periódico, y ese es el paso que siempre se posterga porque no tiene ocasión natural; atarlo a «refrescar staging» se la da.

Staging queda con datos reales de clientes, **y sin credenciales SMTP**. Un `-u` que dispare correo, o una tarea programada que venía en la base restaurada, mandaría mail de verdad a clientes de verdad desde el entorno que existe para romper cosas. Sin el secret, Odoo encola y falla al enviar: visible adentro, inofensivo afuera.

La anonimización se evaluó y se descartó por ahora: es un script que envejece mal, porque protege exactamente los campos que conocía el día que se escribió. Deja de ser opcional si alguna vez entra a staging alguien más que el operador.

## Observabilidad

Solo producción. La latencia y la tasa de error de la capa de aplicación salen del **access log de nginx en JSON** (`$request_time`, `$status`, `$uri`), consultado desde Loki — sin componentes nuevos, porque Alloy ya manda esos logs.

Se descartó un exporter que parsee el log a métricas de Prometheus: es técnicamente mejor y no justifica un contenedor más. `stub_status` no alcanza — da conexiones y un contador de requests, sin latencia ni desglose por código.

**Al migrar, las alertas primero.** Una alerta mal migrada no falla ruidosa: simplemente no dispara nunca.

## Tooling

Los targets de producción llevan guarda explícita, y la guarda le pregunta **a la composición**, no a una variable declarada:

```make
require-prod:
	@docker compose config --services | grep -qx backup || \
	  { echo "$(TARGET): la capa de backups no está en este stack" >&2; exit 2; }
```

Cuelga de `backup`, `backup-full`, `backup-check`, `restore-up` y `restore-down`, y sigue el patrón que ya existe en `require-modules`. Una variable `STACK=` sería una tercera declaración de algo que los entrypoints ya dicen, y divergiría el día que aparezca un cuarto entorno.

`verify.sh` no necesita cambios por esto: ya omite lo que no está corriendo.

## Lo que queda sin efecto

El cambio de proxy se lleva puesto `config/traefik/`, `acme.json`, las labels de Traefik en `compose.odoo.yaml`, el job `traefik` de Prometheus, el dashboard en `127.0.0.1:8080`, los chequeos de Traefik en `verify.sh`, la fase 3 de `INSTALL.md` y dos entradas de `docs/troubleshooting.md`.

**Es el ítem más grande de todo el plan: es reescribir la capa de borde, no configurarla.**

---

# Parte III — Pendientes

**Agujero abierto en producción hoy, no una decisión de diseño.** Nada en el repositorio pide apuntar el DHCP de la LAN a dnsmasq, y el chequeo de `INSTALL.md` usa `dig +short "$HOST_PUB" @"$SRV_LAN"` — ese `@` le pregunta a dnsmasq directamente. Prueba que dnsmasq contesta, no que ningún equipo de la LAN le pregunte. Si el router reparte otro resolver, dnsmasq queda healthy, el chequeo da verde, y la LAN se cae junto con internet igual. La versión que prueba lo que importa es el mismo `dig` **sin** `@`, corrido desde un equipo de la LAN.

Lo demás, arrastrado de antes:

- Bump de `alpine` y de la imagen de Odoo — pendiente de verificar los tags actuales.
- Arreglo de fondo de `PGBACKREST_STANZA`: mover `pg1-path` y `pg1-user` a variables de entorno.
- Umbrales numéricos de las alertas de Grafana, hoy sin parametrizar.
