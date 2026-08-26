# Arquitectura modular de stacks

El diseño acordado para la reorganización del árbol: qué es un stack, qué declara cada
uno y qué declara el entorno que los compone. Registra la decisión, su motivo y lo que
se descartó — las reglas que se desprenden van a [`PRINCIPLES.md`](../PRINCIPLES.md),
la comparación entre entornos a [`stacks.md`](stacks.md).

Varias decisiones acá se apoyan en comportamientos de Compose que **se probaron**, no se
supusieron. Donde es el caso, está el resultado de la prueba.

## Concepto

El repositorio es un **producto**: un catálogo de stacks más una forma de componer un
deploy con ellos. Lo único que varía entre un cliente y otro son **archivos de
configuración**.

> El repo versiona la forma. El cliente solo tiene configs.

Los `compose.yaml`, los entrypoints, los scripts y el `Makefile` son idénticos en todos
los deployments y se actualizan con `git pull` sin conflictos, porque el operador no
toca ninguno. Lo suyo son configs gitignoreados, bootstrapeados con `cp` desde su
`.example`.

De ahí se sigue lo que **no** existe: no hay perfiles de instalación, ni flags que
prendan capas, ni condicionales dentro de un compose. La única superficie adaptable es
un archivo de config.

Se descartó que el entrypoint fuera del cliente (gitignoreado, bootstrapeado como un
config más): agrega un archivo que puede quedar viejo cuando el repo suma un stack, sin
comprar nada.

## La unidad: un stack = un contenedor con cosas propias

Un stack es **una carpeta con un contenedor** y todo lo suyo adentro: su `compose.yaml`,
su imagen, sus configs, su `.env`, sus scripts y sus units.

```
odoo · postgres · nginx · certbot · cloudflared · backup
prometheus · loki · grafana · alloy
```

Más `dnsmasq`, opcional según la topología del cliente — ver «Acceso: LAN o solo túnel».

La palabra operativa es **propias**, no «que corre». La primera versión de esta regla
decía que un contenedor con `profiles:` no era un stack, porque una operación de una vez
no justifica carpeta propia. `certbot` la desmintió: corre treinta segundos por vez, y
aun así tiene imagen, `wrapper.sh`, el secret `cloudflare_api_token`, la unit
`cert-renew`, dos targets del Makefile y sus propios chequeos. Esos archivos existen en
cualquier carpeta donde lo pongas.

> **No es un stack lo que no tiene nada propio.** Eso —y solo eso— vive adentro del que
> sirve. Si tiene imagen, config y superficie operativa, es un stack, corra siempre o a
> demanda.

Dejarlo adentro de `nginx` costaba dos cosas concretas: una convención de anidado
(`image/<servicio>/Dockerfile`) para el único caso de once stacks con más de un
contenedor, y romper el descubrimiento de las units — `cert-renew` se instala solo si
`certbot` está en la composición, y con la unit en `stacks/nginx/systemd/` la carpeta
dueña (`nginx`, siempre presente) no coincide con el servicio que la habilita. Con
`stacks/certbot/`, carpeta y servicio coinciden y la regla es una sola para todas.

Cada entrypoint de entorno compone los stacks con `include:`, listando **todos** los que
lleva, explícitamente. No hay nivel intermedio de agregación por capa.

Se descartó el agregador por capa. El motivo es medido: de cinco capas, solo tres podían
usarlo. `edge` y `backups` no, porque staging y development necesitan subconjuntos —
staging quiere nginx sin dnsmasq, development quiere nginx sin túnel ni certbot— y
**Compose no sabe quitar un servicio de un archivo ya incluido**. Esos dos entrypoints
terminaban listando los archivos sueltos igual. Un nivel que se usa tres de cada cinco
veces es una excepción que hay que recordar; sin él, todos los entrypoints se leen igual
y cada uno es un manifiesto de exactamente qué corre ese entorno.

Se descartó agrupar por responsabilidad operativa (`db` = postgres + pgbouncer, `proxy`
= nginx + certbot). Agrupa bien, pero deja la frontera a criterio: cada servicio nuevo
reabre la discusión de a qué grupo pertenece.

`addons` no es un stack: no tiene contenedor. Es un script.

## Qué declara cada quién

> **Lo que un stack comparte con otro, lo declara el entorno. Lo que es solo suyo, lo
> declara el stack.**

| Recurso | Dueño |
|---|---|
| Redes, secrets, volúmenes compartidos entre stacks (`letsencrypt`) | entrypoint del entorno |
| Volúmenes propios, imagen, config, `.env`, scripts | el stack |
| Qué stacks entran, y qué se les ajusta (`!reset`, `!override`) | entrypoint del entorno |

Compose **fusiona** las declaraciones de nivel superior que llegan por distintos
`include:`, y resuelve cada ruta relativa contra la carpeta del archivo que la escribió.
Así que declarar redes y secrets dentro de cada stack *funciona*, y además deja a cada
carpeta resolviendo sola. No se hace igual, por lo que pasa cuando esas declaraciones
dejan de coincidir:

```yaml
# stack a → networks: {app: }
# stack b → networks: {app: {internal: true}}

networks:
  app:
    internal: true     # ganó b, exit 0, sin una sola advertencia
```

Un stack le cambia la semántica de la red a todos los demás en silencio, y `internal:
true` deja sin salida a internet a todo lo que esté en esa red — un error que aparece en
producción, no en `config`. Lo mismo con dos stacks declarando el mismo secret con
`file:` distintos. Una sola definición elimina esa clase entera de error.

El costo es que un `compose.yaml` de stack no resuelve por sí solo:

```
docker compose config  →  service "postgres" refers to undefined network app
```

No importa: el ciclo de vida por stack lo da el `Makefile` (`make postgres-up`), que
opera contra el entrypoint del entorno, no contra el archivo suelto. La carpeta nunca
necesitó arrancar sola.

## Configuración

**En el `.env` va solo lo que Compose necesita interpolar** — tags de imagen, puertos,
límites de recursos, nombres. Todo lo demás va **literal en el archivo de config de la
herramienta que lo usa**.

La pregunta "¿dónde va este valor?" queda mecánica, sin juicio de por medio:

- ¿Lo interpola Compose? → `.env` del stack.
- ¿No? → el archivo de config de su herramienta.

El efecto buscado es que los valores compartidos desaparezcan. El hostname público deja
de ser un valor en un `.env` que tres stacks leen, y pasa a ser tres literales: uno en el
`.conf` de nginx, uno en el `config.yaml` de cloudflared, uno en `odoo.conf`. No son
copias de un valor que puedan divergir: son tres herramientas configuradas cada una en
su idioma.

Cada stack versiona un `.example` por config; el archivo real va gitignoreado y se
bootstrapea con `cp`.

`include:` acepta que cada stack nombre su propio archivo de entorno, y el mismo stack
corriendo solo lee ese mismo archivo desde su carpeta — probado, incluyendo dos stacks
con distinto valor para la misma clave sin pisarse.

Se descartaron dos niveles de `.env` (uno común del entorno más uno por stack). Evita la
duplicación, pero devuelve la pregunta "¿este valor es transversal?" en cada decisión, y
obliga a mirar dos archivos para saber con qué valor corre un stack.

## Backups: snapshot, no PITR

**Un snapshot de restic contiene el dump de la base y el filestore juntos**, con
retención GFS. No hay archivado de WAL ni recuperación a un punto en el tiempo.

La evidencia que lo respalda es la más pertinente que existe: **Odoo.sh, la plataforma
de Odoo S.A. para sus propios clientes enterprise, hace exactamente esto** — backup
diario, 7 diarios + 4 semanales + 3 mensuales, cada uno con dump, filestore, logs y
sesiones. No ofrece PITR ni lo menciona. El mecanismo oficial on-premise es el mismo: el
zip de `/web/database/manager`.

Los proveedores de Postgres gestionado (RDS, Azure Flexible Server) sí hacen snapshot +
WAL continuo con PITR. Difieren por una razón específica de esta aplicación: **ellos
respaldan una base de datos; en Odoo la base no es todo el estado.** El filestore es la
otra mitad y **no tiene WAL**. Restaurar la base a un punto posterior al último snapshot
del filestore deja filas de `ir_attachment` apuntando a archivos que no se respaldaron —
uno de los modos de falla más documentados de Odoo. El PITR de la base solo sirve hasta
donde llegue el snapshot del filestore, así que la granularidad fina del WAL no compra
nada.

> Para Odoo, **la palanca del RPO es la frecuencia del snapshot, no el WAL.**

El intervalo es la perilla: diario por default, y se baja a 6 h o a 1 h sin cambiar nada
de la arquitectura. restic deduplica y el filestore es append-only, así que un snapshot
frecuente cuesta poco.

### El umbral donde esta decisión se revisa

El costo de un snapshot no escala como el de un incremental físico: `pg_dump` **relee la
base entera** cada corrida, con la producción encima, y un dump comprimido además anula
la deduplicación de restic. A escala grande, un incremental por páginas (pgBackRest)
manda solo lo que cambió y tarda minutos donde el dump tarda horas.

La señal no es el tamaño sino **el tiempo del dump**, que es medible y automatizable:
`backup.sh` avisa cuando `pg_dump` cruza un umbral, y la decisión deja de depender de
que alguien se acuerde de mirar.

### Lo que se elimina con esta decisión

- **La imagen propia de Postgres.** El `Dockerfile` existía solo para instalar
  pgbackrest: `postgres` pasa a la imagen oficial, sin build, sin tag por proyecto.
- `archive_mode`/`archive_command`, y con eso el principio de "un entorno que no
  respalda no archiva WAL" más los `-c archive_mode=off` forzados en staging y development.
- El secret `pgbackrest_r2_credentials`, `pgbackrest.conf` y su `.example`.
- Los targets `stanza-init` y **`restore-password`**. Este último existía porque el
  restore de pgBackRest es físico y copia el cluster entero, roles y contraseñas
  incluidas: el rol `odoo` sembrado se quedaba con la clave del stack de origen. Un dump
  lógico no tiene ese problema.
- El invariante de dos archivos entre la retención de `backup.sh` y la de
  `pgbackrest.conf`. **Una sola retención, en un solo lugar.**
- El servicio `restore-db`: restaurar la base pasa a ser `psql < dump`.

### Un solo contenedor para las dos direcciones

Respaldar y restaurar son la misma herramienta sobre el mismo repositorio, en
direcciones opuestas. Un solo stack, `backup`, hace las dos: separarlos duplicaba el
repositorio de restic en dos `.env` sin comprar nada.

Corren con usuarios distintos, y eso se resuelve en la invocación, no en el árbol: el
servicio se declara **`100:101`** —el uid de Odoo, porque el filestore es 750 y ningún
otro no-root lo lee—, que es la operación recurrente. El restore, que necesita root para
devolverle a cada archivo el owner que tenía en el snapshot, se invoca con
`docker compose run --user 0:0`. Root queda solo para la operación rara y manual.

Y aparece un beneficio estructural: hoy hay que respaldar la base primero y el filestore
después, con las ventanas alineadas, porque son dos repositorios. Con los dos **en el
mismo snapshot**, la consistencia deja de ser un procedimiento y pasa a ser una propiedad.

## Sin pgbouncer

Odoo conecta directo a `postgres:5432`. `db_maxconn = 15` en `odoo.conf` — con
`workers = 4` y `max_cron_threads = 2` son 6 procesos, 90 conexiones contra un
`max_connections` de 100.

pgbouncer existía para poolear entre los workers de un solo Odoo. El precio no era la
memoria: corre en modo transacción, eso rompe `LISTEN/NOTIFY`, y por eso
`server_wide_modules` tenía que incluir `bus_alt_connection` — un módulo cuya ausencia
deja a Odoo arrancando igual y al chat en vivo sin actualizarse, en silencio. También se
van el secret `pgbouncer_credentials`, su `.ini` y el `auth_type = plain`.

Lo que se pierde: `PAUSE`/`RESUME` antes de un restore, y el colchón si `db_maxconn`
queda mal — Postgres rechaza en vez de encolar. Con una sola aplicación en un solo
servidor, no pagaba su costo. Se justifica con más concurrencia o más de una app contra
la misma base.

## Acceso: LAN o solo túnel

Las cuatro piezas del borde no son cuatro decisiones. `cloudflared` y `nginx` van
siempre; `dnsmasq` y `certbot` cuelgan de una sola pregunta.

**`cloudflared`** es el túnel saliente: lo que permite cumplir "ningún puerto abierto en
el router". No tiene alternativa dentro del stack.

**`nginx`** separa `/websocket` (8072) del resto (8069), pone los headers que
`proxy_mode` necesita, aplica el **rate-limit del login** que exige `PRINCIPLES.md`, y
termina TLS para la LAN. cloudflared podría hacer el split de puertos con sus reglas de
ingress, pero el rate-limit se mudaría al WAF de Cloudflare —fuera del repositorio y
dependiente del plan— y por la LAN no pasa cloudflared en absoluto.

**`dnsmasq`** resuelve el hostname público a la IP local, para que los equipos de la red
no salgan a internet para llegar a un servidor que tienen al lado. **`certbot`** existe
para que nginx tenga certificado propio, y nginx lo necesita **solo** porque el tráfico
de la LAN esquiva el borde de Cloudflare. Los dos cuelgan de lo mismo:

```
¿Hay servidor local, con usuarios en la misma red?
├── NO  (VPS)       → cloudflared + nginx          todo el tráfico sale por el túnel
└── SÍ  (in-house)  → + dnsmasq + certbot
```

Es la única variación real entre clientes, y afecta solo a producción: prueba y
desarrollo nunca llevan ninguno de los dos.

Se resuelve con **`profiles: [lan]` en dnsmasq y `COMPOSE_PROFILES=lan` en el `.env` del
cliente** — probado:

```
.env sin COMPOSE_PROFILES      →  nginx
.env con COMPOSE_PROFILES=lan  →  nginx, dnsmasq
```

El entrypoint de producción sigue siendo **uno solo, versionado e idéntico para todos**;
la topología vive en el archivo que el cliente ya posee, en una línea.

`certbot` no necesita el profile: ya es un one-off, así que en un VPS simplemente nunca
se invoca. Y la diferencia de nginx entre los dos casos —servir TLS o servir plano al
túnel— ya la resuelve **cuál config monta**, que es un archivo real del cliente.

Se descartó un cuarto entrypoint (producción en VPS y producción con servidor local):
duplica un archivo versionado para expresar lo que una línea del `.env` ya expresa.

### Cuándo `profiles` y cuándo composición

`backup` no se apaga con `profiles` y `dnsmasq` sí, y no es una excepción: los modos de
falla son opuestos.

| Activado por accidente | Consecuencia |
|---|---|
| `backup` en prueba | escribe en el repositorio de producción y apaga su alerta — **silencioso y destructivo** |
| `dnsmasq` en un VPS | no puede bindear el 53 y falla al arrancar — **ruidoso e inofensivo** |

> **Composición donde la activación accidental es destructiva. `profiles` donde es
> inofensiva.**

## Entornos

**Un entorno por checkout.** Cuál es lo dice el `.env` del checkout, no la ruta de un
archivo. No existe `config/production/` ni ningún otro subdirectorio por entorno: los
stacks quedan idénticos en forma, sin excepciones.

Se descartó el subdirectorio por entorno dentro de cada stack. Superpone dos
aislamientos —el del checkout y el de la ruta— y el resultado es uno que no aísla nada,
por el mismo motivo que el árbol de addons es uno por checkout.

Los entrypoints **difieren en composición**, porque la naturaleza de cada entorno es
distinta:

| Entorno | Naturaleza |
|---|---|
| Producción | Datos reales. Todo resguardado y monitoreado. |
| Prueba | Sandbox controlado: validar features antes de producción. |
| Desarrollo | Construcción de módulos e ideas. Servidor o máquina del desarrollador. |

Prueba no lleva observabilidad. Sí lleva `backup`, porque se siembra restaurando el
snapshot de producción y respaldar y restaurar son ahora el mismo contenedor. Desarrollo
lleva `nginx`, `postgres` y `odoo`.

### Que prueba no respalde, con el contenedor fusionado

Mientras `backup` y `restore` eran dos servicios, la garantía era estructural por
ausencia: prueba no incluía `backup`, así que no había config que pudiera equivocarse.
Fusionarlos tiene ese costo, y la garantía se reconstruye en dos capas, ninguna de las
cuales es "un archivo bien completado":

- **El camino automático** lo da el timer de systemd, que se instala solo en producción.
  Sin timer, el contenedor de prueba no respalda nunca por su cuenta: se queda esperando
  a que alguien le pida un restore.
- **El camino manual** —un `make backup-run` tipeado en el checkout equivocado— lo corta la
  credencial: el token de R2 de prueba es **de solo lectura**. El restore funciona; la
  escritura falla en el proveedor, no en un `if`. Es la misma regla de tokens acotados al
  permiso mínimo que el stack ya aplica en todos lados, y es verificable: la verificación
  de prueba puede afirmar que ese token no puede escribir.

Es más débil que "el servicio no existe" y conviene decirlo así. A cambio, elimina la
duplicación del repositorio de restic en dos stacks y deja una sola herramienta de
respaldos.

Se descartó incluir todos los stacks en los tres entornos y apagar `backup` con
`profiles`: convierte una garantía estructural en un archivo bien completado. La regla
que separa los dos mecanismos está en «Acceso: LAN o solo túnel» — no es una excepción,
depende de qué pasa cuando algo se activa por accidente.

Producción y prueba conviven en un servidor. No colisionan porque el nginx de prueba no
publica puertos — se alcanza por el túnel, que sale hacia afuera y no necesita ninguno.

El entrypoint no solo elige stacks: también **ajusta los que eligió**, con `!reset` y
`!override` al lado del `include:` que los trajo. Es la pieza que permite que un stack
sirva a tres entornos sin llevar un solo condicional adentro.

## Scripts

Cada stack trae los scripts que operan ese stack — `postgres/verify.sh`,
`backup/backup.sh`. Arriba quedan solo los transversales: `secrets-init.sh`,
`addons.sh`, y un `verify` que **orquesta**: corre el de cada stack presente y junta
resultados, sin saber qué espera ninguno.

Cambia el dueño único de las verificaciones, no lo elimina: pasa de un archivo que sabe
qué se espera de todas las piezas, a un dueño por stack, más chico y al lado de lo que
describe. Agregar un stack deja de tocar el verificador global.

## Acoplamientos que ninguna forma de árbol disuelve

`prometheus` y `alloy` scrapean por nombre de contenedor, y `nginx` rutea a `odoo` por
nombre. Son acoplamientos de naturaleza, no de forma: separarlos en carpetas no los
desacopla, solo los esconde detrás de un `../`.

## Decisiones abiertas

**Frecuencia del snapshot.** Diario es el default de Odoo.sh y el punto de partida
razonable. Cuál es el RPO tolerable para un deployment concreto es del operador.

## Pendiente

`CLAUDE.md` y `PRINCIPLES.md` describen la arquitectura anterior en prosa y quedan
invalidados por este documento. La deduplicación entre esos dos archivos —hoy repiten
once reglas, varias casi textuales— conviene hacerla con esta forma ya implementada, no
antes.

## La estructura

```
odoo-infrastructure/
│
├── .env                         ← identidad del checkout: COMPOSE_PROJECT_NAME + COMPOSE_FILE
├── Makefile
│
├── envs/                        ← un entrypoint por entorno: redes, secrets, includes, ajustes
│   ├── production.yaml
│   ├── staging.yaml
│   └── development.yaml
│
├── stacks/                       ← cada stack: compose.yaml en la raíz, image/ y config/ adentro
│   ├── odoo/
│   │   ├── compose.yaml
│   │   ├── image/
│   │   │   ├── Dockerfile
│   │   │   └── entrypoint.sh    ← COPYado por el Dockerfile, vive junto a él
│   │   ├── config/
│   │   │   ├── odoo.conf.example    ← versionado
│   │   │   └── odoo.conf            ← real, gitignoreado, `cp` desde el .example
│   │   └── verify.sh
│   │
│   ├── postgres/
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile     ← FROM postgres:17.10, sin capas propias
│   │   ├── config/
│   │   │   ├── postgresql.conf.example
│   │   │   └── postgresql.conf
│   │   └── verify.sh
│   │
│   ├── nginx/
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile     ← FROM nginx:1.31.3-alpine, sin capas propias
│   │   ├── config/
│   │   │   ├── 00-http.conf.example · server-tls.conf.example · odoo.locations.example
│   │   │   └── server-plain.conf    ← versionado tal cual: no lleva nada por deployment
│   │   ├── .env.example         ← LOCAL_IP, HTTP_PORT, HTTPS_PORT
│   │   └── verify.sh
│   │
│   ├── certbot/                 ← profiles: [cert] — one-off, pero con todo lo suyo
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile
│   │   ├── scripts/wrapper.sh   ← bind-mount, no COPY: es runtime, no build
│   │   ├── systemd/cert-renew.{service,timer}
│   │   └── verify.sh
│   │
│   ├── cloudflared/
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile
│   │   ├── config/{config.yaml.example,config.yaml}
│   │   └── verify.sh
│   │
│   ├── dnsmasq/                 ← profiles: [lan]
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile
│   │   ├── config/{dnsmasq.conf.example,dnsmasq.conf}
│   │   └── verify.sh
│   │
│   ├── backup/                  ← respaldar y restaurar, mismo contenedor
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile
│   │   ├── scripts/{backup.sh,restore.sh}
│   │   ├── config/{r2.env.example,r2.env}
│   │   ├── systemd/backup-{daily,monthly}.{service,timer}
│   │   └── verify.sh
│   │
│   ├── prometheus/ · loki/ · grafana/ · alloy/
│   │       cada uno: compose.yaml · image/Dockerfile · config/ (.example + real) · verify.sh
│   │
├── scripts/                     ← solo lo transversal
│   ├── verify.sh                ← orquesta: corre el de cada stack presente
│   ├── secrets-init.sh · secrets-perms.sh
│   ├── addons.sh
│   ├── timers.sh
│   └── lib/ui.sh
│
├── host/
│   ├── daemon.json              ← rotación de logs, global al daemon
│   └── systemd/notify@.service  ← transversal: la usan los timers de cualquier stack
│
├── secrets/                     ← gitignoreado
├── addons/                      ← gitignoreado por contenido
├── tests/
└── docs/
```

### Adentro de un stack: image/, config/, scripts/

Tres carpetas, mismo criterio en las once: **por qué existe el archivo, no qué tipo de
archivo es**.

- **`image/`** — lo que participa del build: el `Dockerfile` y todo lo que ese
  `Dockerfile` hace `COPY` (el `entrypoint.sh` de `odoo` vive ahí, al lado, no en
  `scripts/`, porque se copia adentro de la imagen).
- **`config/`** — lo que la herramienta lee en runtime: `.example` versionado, real
  gitignoreado al lado.
- **`scripts/`** — lo que un humano o un timer invocan desde el host, sin pasar por el
  build: `backup.sh`, `certbot-wrapper.sh`. No existe si el stack no tiene nada así.

`compose.yaml` se queda en la raíz del stack, nunca adentro de una subcarpeta: es lo que
`envs/*.yaml` nombra por `include:`, y ese camino tiene que ser predecible sin mirar
adentro de cada stack.

**Todo stack tiene `image/Dockerfile`, incluso sin nada que agregarle a la imagen
oficial.** `postgres` y `nginx` son casos así: dos líneas, un `FROM` pineado y nada más.
Es deliberado — la alternativa es `image: postgres:17.10` directo en el compose, sin
build, que dice exactamente lo mismo en una línea y sin capa extra. El costo real: dejar
de pullear el tag oficial y pasar a construir sobre él en cada checkout, y `make up`
sobre un checkout nuevo necesita un `build` antes del primer `up` para los once stacks,
no solo para los que de verdad compilan algo. Se paga a cambio de que ningún stack sea la
excepción — el día que `postgres` necesite algo instalado, es una línea en un archivo que
ya existe, no una carpeta nueva.

### Lo que hace que esto se lea solo

**Todos los stacks están a la misma profundidad.** `stacks/<nombre>/`, sin excepción. Por
eso la ruta de un stack a cualquier cosa compartida es siempre `../../`, idéntica en los
once — no hay que contar carpetas.

**El nombre del stack es el nombre del contenedor.** No hay traducción entre lo que decís
(`make grafana-logs`), lo que ves (`stacks/grafana/`) y lo que corre.

**Los `.example` viven al lado de su archivo real.** El bootstrap es siempre el mismo
gesto en la misma carpeta, y una verificación puede afirmar que ningún `.example` quedó
sin copiar sin saber nada de cada herramienta.

**Los timers viven con su stack.** `cert-renew` con nginx, los de backup con backup: un
stack trae todo lo suyo, incluido lo que se instala fuera del checkout. Arriba queda solo
`notify@.service`, que cualquier timer usa.

**Casi ningún stack tiene `.env`.** Es la regla de configuración funcionando: los tags
van pineados literales en el compose, y lo que no interpola Compose vive en el config de
su herramienta. `nginx` es de los pocos que necesita uno, porque publica puertos.
