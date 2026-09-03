# Arquitectura

Qué es esto, cómo se relaciona con los repositorios de módulos, por qué cada
herramienta y no otra, qué es un stack y qué declara cada quién, qué comparten los
entornos, y el mapa completo para levantar un Odoo funcional. Las reglas que se
desprenden de estas decisiones están en [`PRINCIPLES.md`](PRINCIPLES.md); los
procedimientos ejecutables, en [`docs/`](docs/).

Varias decisiones acá se apoyan en comportamientos de Compose que **se probaron**, no se
supusieron. Donde es el caso, está el resultado de la prueba.

---

## Qué es esto

Un **producto**: un catálogo de stacks —contenedores— más una forma de componerlos en
un deploy, para correr Odoo autoalojado, operado por una sola persona sobre un único
servidor.

> El repo versiona la forma. El operador solo aporta configs.

Los `compose.yaml`, los entrypoints, los scripts y el `Makefile` son idénticos en todos
los deployments y se actualizan con `git pull` sin conflictos, porque el operador no
toca ninguno. Lo suyo son configs gitignoreadas, bootstrapeadas con `cp` desde su
`.example`.

De ahí se sigue lo que **no** existe: no hay perfiles de instalación, ni flags que
prendan capas, ni condicionales dentro de un compose. La única superficie adaptable es
un archivo de config.

No es un framework de propósito general ni una plataforma multi-tenant. Es la
infraestructura de **una** instancia de Odoo, pensada para que un solo operador la
levante, la entienda entera y la mantenga sin depender de un equipo.

Se descartó que el entrypoint fuera del cliente (gitignoreado, bootstrapeado como un
config más): agrega un archivo que puede quedar viejo cuando el repo suma un stack, sin
comprar nada.

### Dos tipos de repositorio, una sola orquestación

Este repositorio **no contiene código de aplicación**. Es infraestructura pura:
contenedores, config, scripts, `Makefile`. El código de cada módulo de Odoo —propio,
forkeado de OCA o de terceros— vive en **otro repositorio git**, uno por módulo, ajeno
a este.

La relación entre ambos es de **orquestación, no de contención**: este repo no
incorpora ese código a su propia historia — lo clona, lo actualiza y lo monta. Lo único
que sabe de cada módulo es una línea en `addons/addons.txt`: su URL y su categoría
(`enterprise` · `custom-addons` · `oca` · `third-party`, el mismo orden que resuelve el
`addons_path` — ver «Gestión de addons: bind-mount» más abajo). `make repo-sync` recorre ese
manifiesto, clona cada repo en bare y arma un worktree por módulo sobre la rama que
declara el checkout — el mecanismo completo está en los comentarios de
[`scripts/addons.sh`](scripts/addons.sh). El resultado es un árbol en disco que el
contenedor de Odoo monta `:ro`; el contenedor nunca clona nada, y el entrypoint arma el
`addons_path` recorriendo ese árbol por glob.

Así, "levantar Odoo" combina siempre dos gestos distintos: `git pull` en **este**
repositorio trae una versión nueva de la infraestructura; `make repo-sync` trae el
estado más reciente de **los módulos**. Son independientes — se puede actualizar uno
sin el otro.

**Qué no es este repositorio:**

- No versiona código de módulos de Odoo, ni siquiera pineado por commit.
- No es el lugar para desarrollar un módulo — eso pasa en el repo de ese módulo,
  clonado como worktree bajo `addons/`; ver [`docs/modulos/gestionar-modulo.md`](docs/modulos/gestionar-modulo.md).
- No guarda datos ni estado del deployment: eso vive en volúmenes nombrados y en los
  backups, no en el checkout — un `git pull` acá nunca toca datos.
- No es específico de ningún cliente: valores que solo sirven a un deployment concreto
  —hostnames, IPs, proveedores como ejemplo obligatorio— son un defecto acá, no un
  detalle.

## Objetivo de robustez

Con un solo servidor, "robusto" prioriza en este orden:

1. **Evitar pérdida de datos.**
2. **Visibilidad operativa** — detectar y diagnosticar caídas rápido.

Alta disponibilidad real queda fuera de alcance: no es alcanzable con un único
servidor, así que ninguna decisión se toma para acercarse a ella.

---

## La unidad: un stack = un contenedor con cosas propias

Un stack es **una carpeta con un contenedor** y todo lo suyo adentro: su `compose.yaml`,
su imagen, sus configs, su `.env`, sus scripts y sus units.

```
odoo · postgres · nginx · certbot · cloudflared · backup
prometheus · loki · grafana · alloy
```

Más `dnsmasq`, opcional según la topología del cliente — ver «`dnsmasq` y `certbot`: cuándo entran».

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

`addons` no es un stack: no tiene contenedor. Es un script — el que orquesta la
relación con los repositorios de módulos descripta arriba.

### Modularización de Compose

Cada entrypoint de entorno compone los stacks con `include:`, listando **todos** los que
lleva, explícitamente — un archivo por stack, nunca uno monolítico. `envs/production.yaml`
no declara servicios propios: declara los recursos compartidos —`networks:`, `secrets:`
y los volúmenes que dos stacks comparten— y suma **un archivo por stack** con `include:`.

- **Motivo:** un archivo por stack mantiene acotado el diff de cada cambio y hace
  auditable de un vistazo qué contenedores lleva ese entorno. Más fácil de revisar y de
  razonar sobre el radio de impacto que un archivo de cientos de líneas con todo
  mezclado.
- **Mecanismo:** `include:` en vez de encadenar `-f` a mano en cada invocación, lo que
  evita que una invocación se olvide un archivo y levante un subconjunto incompleto sin
  avisar.
- **Naming:** nunca `compose.override.yaml`. Ese nombre dispara el autoload especial de
  Compose —se aplica implícitamente sin pedirlo— y confunde la semántica: esto es
  modularización, con servicios distintos que no se solapan, no override de ambiente.

**Se descartó un nivel intermedio de agregación por capa** (un archivo `edge.yaml` que
incluyera nginx, certbot, cloudflared y dnsmasq). El motivo es medido: de cinco capas
solo tres podían usarlo. `edge` y `backups` no, porque staging y development necesitan
subconjuntos —staging quiere nginx sin dnsmasq, development quiere nginx sin túnel ni
certbot— y **Compose no sabe quitar un servicio de un archivo ya incluido**. Esos dos
entrypoints terminaban listando los archivos sueltos igual. Un nivel que se usa tres de
cada cinco veces es una excepción que hay que recordar; sin él, todos los entrypoints se
leen igual y cada uno es un manifiesto de exactamente qué corre ese entorno.

**Se descartó agrupar por responsabilidad operativa** (`db` = postgres + pgbouncer,
`proxy` = nginx + certbot). Agrupa bien, pero deja la frontera a criterio: cada servicio
nuevo reabre la discusión de a qué grupo pertenece.

**Cada entorno tiene su propio entrypoint completo**, no un archivo chico que pise al de
producción: `envs/staging.yaml` y `envs/development.yaml` listan sus propios `include:`,
sus propios secrets y sus propios ajustes con `!override`. Cuál se levanta lo dice
`COMPOSE_FILE` en el `.env` del checkout, así que no existe una cadena por defecto de la
que un entorno pueda quedar dentro por descuido.

### Qué declara cada quién

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
bootstrapea con `cp`. `include:` acepta que cada stack nombre su propio archivo de
entorno, y el mismo stack corriendo solo lee ese mismo archivo desde su carpeta —
probado, incluyendo dos stacks con distinto valor para la misma clave sin pisarse.

Se descartaron dos niveles de `.env` (uno común del entorno más uno por stack). Evita la
duplicación, pero devuelve la pregunta "¿este valor es transversal?" en cada decisión, y
obliga a mirar dos archivos para saber con qué valor corre un stack.

---

## Capa de datos

**Redis: no.** Se evaluó como backend del bus de notificaciones, que por defecto usa
`LISTEN/NOTIFY` de Postgres. El worker gevent que maneja el bus queda siempre en un
proceso, sin importar la cantidad de workers HTTP, así que no escala con ellos. Lo que
justificaría Redis es volumen alto de notificaciones concurrentes o varias instancias
compartiendo el bus; con un solo servidor no aplica ninguno. Agregarlo después es un
parámetro de config, sin rearmar nada.

**PgBouncer: no.** Odoo conecta directo a `postgres:5432`. `db_maxconn = 15` en
`odoo.conf` — con `workers = 4` y `max_cron_threads = 2` son 6 procesos, 90 conexiones
contra un `max_connections` de 100. Lo que justificaría un pooler es que el límite de
conexiones por proceso de Odoo dé un techo por encima del `max_connections` de Postgres
— pero con una sola aplicación en un solo servidor eso se resuelve con **un valor**:
`db_maxconn` por la cantidad de procesos tiene que entrar en `max_connections`. Es una
cuenta, no una pieza de infraestructura.

El precio del pooler no era la memoria: corre en **modo transacción**, eso rompe
`LISTEN/NOTIFY`, y por eso Odoo necesitaba `bus_alt_connection` en `server_wide_modules`
para darle al bus su propia conexión directa — un módulo cuya ausencia deja a Odoo
arrancando igual y al chat en vivo sin actualizarse, en silencio. También se iba un
secret con la contraseña en texto plano —`auth_type = plain`— y el procedimiento entero
de reaplicar esa credencial después de restaurar.

Lo que se pierde: `PAUSE`/`RESUME` antes de un restore, y el colchón si `db_maxconn`
queda mal — Postgres rechaza en vez de encolar. **Sin pooler, pasarse no encola:
Postgres rechaza.** Se revisita con más concurrencia, o si más de una aplicación
comparte la base. Los dos valores que hoy sostienen la decisión los cruza
`postgres-verify`: viven en archivos de herramientas distintas y nada más los ata.

**Versión de Postgres:** la estable más reciente compatible, no la mínima. Al no
tratarse de una migración desde una versión vieja, maximiza el tiempo antes de quedar
desactualizada.

**Tuning de memoria.** Lo que importa es el método, no los números: los parámetros se
calculan **como ratio del cap de memoria del contenedor, no de la RAM del host**.
Postgres no es el inquilino principal —la aplicación lo es— así que se lo acota con un
`mem_limit` explícito y el resto se deriva de ahí. `effective_cache_size` es una pista
para el planner, no una reserva, y se deja conservador porque la page cache del sistema
se comparte con todo lo demás.

---

## Aplicación

**Workers: por debajo de lo que da la fórmula.** La fórmula estándar asume que la
aplicación tiene el servidor para ella sola. Cuando comparte host con la base, el resto
del stack y cualquier otra cosa, el número se ajusta hacia abajo y se acompaña de
límites de memoria por proceso, más un `mem_limit` de contenedor que cubra la suma con
margen — para que el reciclado propio de Odoo gane al OOM-kill de Docker.

**`proxy_mode` habilitado.** No es una decisión con alternativa real: se desprende de
tener un reverse proxy adelante. Sin eso, Odoo no detecta correctamente HTTPS ni la IP
de origen.

**SMTP: servicio transaccional de terceros.** Mismo patrón que usar storage gestionado
en vez de mantenerlo uno mismo — reputación de IP, SPF, DKIM y DMARC ya resueltos,
evitando el riesgo de deliverability de un servidor de correo autoalojado. Se configura
como servidor saliente por defecto en el archivo de config, y no como registro en la
base desde la UI: ese registro es estado que no sobrevive a un rebuild ni se expresa
como código, mientras que el default del archivo es config versionada. Regla operativa
que se desprende: no crear servidores salientes desde la interfaz.

**Upgrade de versión mayor.** En la edición comunitaria, la vía es el proyecto de
migración de la comunidad, porque el fabricante no ofrece servicio oficial para esa
edición. Detalle práctico: los scripts de migración suelen tardar cerca de un año en
madurar tras cada release, lo que conviene tener en cuenta al planificar.

### Gestión de addons: bind-mount

Los módulos **no se hornean en la imagen**: se montan `:ro` desde el árbol en disco que
arma `make repo-sync` (ver «Dos tipos de repositorio, una sola orquestación» arriba).

**El motivo es el costo de deploy.** Con los repos pineados a commit dentro de la
imagen, cambiar una línea de un módulo propio costaba cinco pasos —commit en el módulo,
bump del hash, commit acá, rebuild, restart—, o sea un ciclo de build completo por cada
corrección. Con bind-mount son dos: sincronizar el árbol y actualizar el módulo en la
base. El pineo era proporcionado para módulos de terceros, que casi no se mueven, y
desproporcionado para los propios en desarrollo activo.

**El pineo no se pierde: cambia de naturaleza.** Deja de ser una declaración mantenida a
mano y pasa a ser una **observación registrada automáticamente** — la corrida de backup
vuelca repo, rama y commit de cada worktree dentro del snapshot, así que un restore sabe
a qué código volver sin que nadie tenga que acordarse en cada deploy.

**Un repo por módulo, dos ramas fijas por entorno.** Producción y staging, con el
desarrollo en ramas de feature. La rama de staging se resetea a la de producción antes
de cada feature, así que staging es siempre *producción más exactamente un cambio* y
queda **descartable en todo momento**: nunca contiene nada que no exista además en una
rama de feature o en producción. Eso permite serializar features sin cherry-picks,
porque promover sube exactamente lo que se validó.

**Los módulos de terceros se forkean a la organización propia**, con el original como
segundo remote. Un solo modelo para todos los repos, y habilita parchear un módulo ajeno
sin salir de él — que era el argumento fuerte a favor de una herramienta agregadora y la
razón por la que se habían descartado los submodules. Lo que se pierde a conciencia es
combinar una rama base con PRs sueltos sin mergear; con forks eso se resuelve mergeando
el PR en la rama propia: más trabajo manual, sin una herramienta que mantener, y con el
resultado visible en el historial.

**El servidor es réplica de solo lectura.** Todos los merges ocurren en la máquina del
operador; el servidor solo trae cambios. Nada de lo que hay en ese disco es
irrecuperable, y por eso la credencial de git es de solo lectura.

**Sobrevive un Dockerfile mínimo.** Se evaluó eliminar el build por completo y se
descartó: los módulos declaran dependencias de Python, y sin imagen propia no hay dónde
instalarlas. El build queda disparado solo por un cambio de dependencias o del
entrypoint, nunca por un addon — que es exactamente lo que se buscaba.

**Precedencia si dos módulos coinciden en nombre:** `enterprise` > `custom-addons` >
`oca` > `third-party` > core. La arma el entrypoint recorriendo las categorías en ese
orden, por glob y no por un listado a mano. **Advertencia:** Odoo no documenta la
precedencia del `addons_path`; este orden se apoya en convención, no en una fuente
normativa.

---

## Borde y red

Las cuatro piezas del borde no son cuatro decisiones. `cloudflared` y `nginx` van
siempre; `dnsmasq` y `certbot` cuelgan de una sola pregunta.

**Ingreso: túnel saliente hacia el borde del CDN (`cloudflared`).** Conexión desde el
servidor hacia afuera, sin puertos abiertos en el router, sin exponer la IP pública, y
con filtrado de tráfico malicioso antes de llegar a la red local. Descartados:
exposición directa del `80`/`443` en el router, y usar el CDN solo como DNS. No tiene
alternativa dentro del stack.

El túnel se administra desde el dashboard del proveedor, así que el mapeo de hostname
público a servicio interno **no queda como código en este repositorio**. Es la única
pieza del borde en esa situación, y es una consecuencia asumida.

**Modelo de exposición:** solo la aplicación tiene hostname público. Ninguna UI
administrativa lo recibe — reduce quién puede siquiera intentar llegar a un login, sin
importar qué tan bueno sea ese login.

### El criterio de bind

El hallazgo que lo motiva: **Docker publica por DNAT e inserta sus reglas antes de las
cadenas del firewall**, así que un `deny` no bloquea un puerto publicado por un
contenedor. El bind, en cambio, es control del kernel: no hay regla que lo saltee.

De ahí los cuatro niveles —sin `ports:`, loopback, IP de la LAN, `network_mode: host`— y
la prohibición de `0.0.0.0`. El firewall del host queda acotado a lo que sí gobierna:
los puertos de procesos del host.

**La red privada de administración llega al servidor, no a los servicios.** Ningún
contenedor se ata a su IP. Además de acotar la superficie, evita un modo de falla
concreto: ese bind falla con `cannot assign requested address` si la interfaz no está
arriba cuando Docker levanta el contenedor, y con `restart: unless-stopped` el servicio
queda en loop tras un reboot.

### `nginx`: reverse proxy

Config en archivos, no descubrimiento por labels. La elección se revisó al planificar el
segundo y el tercer entorno, y ahí el auto-discovery deja de ser una ventaja: el
provider de Docker no está acotado al proyecto, así que con dos stacks en el mismo host
cada proxy descubre los contenedores del otro y arma routers duplicados hacia backends
que no alcanza. Config estática lo vuelve imposible por construcción, y además saca el
socket de Docker de un servicio expuesto a internet.

`nginx` separa `/websocket` (8072) del resto (8069), pone los headers que `proxy_mode`
necesita, aplica el **rate-limit del login** que exige `PRINCIPLES.md`, y termina TLS
para la LAN. `cloudflared` podría hacer el split de puertos con sus reglas de ingress,
pero el rate-limit se mudaría al WAF de Cloudflare —fuera del repositorio y dependiente
del plan— y por la LAN no pasa `cloudflared` en absoluto.

Se paga en dos monedas. **Los certificados dejan de ser gratis:** nginx no hace ACME,
así que aparece `certbot` como componente nuevo, con su propio timer y su propio modo de
falla — una renovación que falla en silencio, que es lo que cubre el `OnFailure=`. Y
**las métricas de capa de aplicación hay que reconstruirlas:** nginx OSS solo expone
`stub_status` —conexiones y un contador de requests, sin latencia ni códigos—, así que
la latencia y la tasa de error salen del access log en JSON, consultado desde Loki. Se
descartó un exporter que parsee ese log a métricas de Prometheus: es técnicamente mejor
y no justifica un contenedor más.

El mismo nginx corre en los tres entornos, sin TLS en desarrollo. Que el proxy exista
también ahí es deliberado: es lo que hace honesto al `proxy_mode = True` de
`odoo.conf`, que sin nadie escribiendo `X-Forwarded-*` confía en cabeceras que no
existen.

**TLS: certificado propio vía desafío DNS-01 (`certbot`).** No alcanza con que el CDN
termine TLS en su borde, porque el acceso por red local lo evita por completo. DNS-01 y
no HTTP-01 porque no requiere el puerto 80 público — compatible con cero puertos
abiertos. El resultado es cifrado de punta a punta en los tres tramos. `certbot` existe
solo porque el tráfico de la LAN esquiva el borde de Cloudflare.

**Acceso por red local: `dnsmasq`.** Resuelve el hostname público a la IP local, para
que los equipos de la red no salgan a internet para llegar a un servidor que tienen al
lado. Preferido sobre Pi-hole o AdGuard Home, más pesados y con funciones no pedidas
para un problema que se resuelve con una línea de config. Beneficio adicional para el
objetivo de robustez: **este camino no depende del túnel ni de internet**. Salvedad:
esquiva el filtrado del borde, así que es una postura de seguridad distinta a la del
acceso público.

**Fuerza bruta en el login: rate-limit en el proxy.** Cuenta requests sin importar éxito
o fallo, así que frena tráfico automatizado de alto volumen antes de que llegue a la
aplicación. Se verificó que el rate-limiting que documenta Odoo es específico de su nube
y no viene en una instalación autoalojada — de ahí el ecosistema de módulos de terceros
para agregarlo.

### `dnsmasq` y `certbot`: cuándo entran

Es la única variación real entre clientes, y afecta solo a producción: prueba y
desarrollo nunca llevan ninguno de los dos.

```
¿Hay servidor local, con usuarios en la misma red?
├── NO  (VPS)       → cloudflared + nginx          todo el tráfico sale por el túnel
└── SÍ  (in-house)  → + dnsmasq + certbot
```

Se resuelve con **`profiles: [lan]` en dnsmasq y `COMPOSE_PROFILES=lan` en el `.env` del
cliente** — probado:

```
.env sin COMPOSE_PROFILES      →  nginx
.env con COMPOSE_PROFILES=lan  →  nginx, dnsmasq
```

El entrypoint de producción sigue siendo **uno solo, versionado e idéntico para todos**;
la topología vive en el archivo que el cliente ya posee, en una línea. `certbot` no
necesita el profile: ya es un one-off, así que en un VPS simplemente nunca se invoca. Y
la diferencia de nginx entre los dos casos —servir TLS o servir plano al túnel— ya la
resuelve **cuál config monta**, que es un archivo real del cliente.

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

---

## Backups

**El requisito que lo dispara:** poder recuperar la instalación entera —datos y
adjuntos— a un estado consistente, sin depender de nada que solo exista en el servidor
de origen.

**Storage: Cloudflare R2.** El motivo principal es que no cobra egress, y en backups el
costo real aparece al *restaurar* — justo en el momento de un desastre. Descartados: S3
(maduro pero cobra egress, un costo inesperado durante una recuperación real) y
Backblaze B2 (barato, pero un proveedor separado más que gestionar).

**Una sola herramienta, restic.** Deduplicación real y cifrado nativo, y sube directo a
storage S3-compatible sin transporte adicional. El dump de la base y el filestore van
**en el mismo snapshot**.

### Snapshot y no PITR

Se evaluó archivado continuo de WAL con pgBackRest, que da un RPO de minutos para la
base, y **se descartó**. La evidencia más pertinente es que **Odoo.sh —la plataforma de
Odoo S.A. para sus propios clientes enterprise— respalda por snapshot**: backup diario
con retención GFS de 7 diarios, 4 semanales y 3 mensuales, cada uno con dump, filestore,
logs y sesiones. No ofrece PITR ni lo menciona. El mecanismo oficial on-premise es el
mismo: el zip de `/web/database/manager`.

Los proveedores de Postgres gestionado (RDS, Azure Flexible Server) sí hacen snapshot
más WAL continuo. Difieren por una razón específica de esta aplicación: **ellos
respaldan una base de datos, y en Odoo la base no es todo el estado.** El filestore es
la otra mitad y no tiene WAL. Restaurar la base a un punto posterior al último snapshot
del filestore deja filas de `ir_attachment` apuntando a archivos que nunca se
respaldaron — uno de los modos de falla más documentados de Odoo. El PITR de la base
solo sirve hasta donde llegue el snapshot del filestore, así que la granularidad fina
del WAL no compra nada.

> Para Odoo, **la palanca del RPO es la frecuencia del snapshot, no el WAL.**

El intervalo es la perilla: diario por default, y se baja a 6 h o a 1 h sin cambiar nada
de la arquitectura. restic deduplica y el filestore es append-only, así que un snapshot
frecuente cuesta poco.

**El umbral donde esta decisión se revisa** no es el tamaño sino el tiempo del dump.
`pg_dump` relee la base entera en cada corrida, y un dump comprimido además anula la
deduplicación de restic —zlib cambia el flujo de bytes globalmente ante cualquier
modificación—, así que el dump va sin comprimir y se paga leer todo cada noche. A escala
grande, un incremental por páginas (pgBackRest) manda solo lo que cambió y tarda minutos
donde el dump tarda horas. `backup.sh` avisa al cruzar el umbral, para que la decisión
no dependa de que alguien mire.

**Retención GFS, en un solo lugar.** 7 diarios, 4 semanales, 3 mensuales, aplicados por
`restic forget --prune` en la corrida diaria. Con una sola herramienta desaparece el
invariante de dos archivos que había que cruzar entre dos ventanas de retención
distintas.

**Lo que se eliminó al migrar de pgBackRest a este esquema:**

- Las capas propias de la imagen de Postgres. El `Dockerfile` instalaba pgbackrest; sin
  eso queda un `FROM postgres:17.10` pelado. El archivo **no** desaparece: todo stack
  construye su imagen, incluso sin nada que agregarle.
- `archive_mode`/`archive_command`, y con eso el principio de "un entorno que no
  respalda no archiva WAL" más los `-c archive_mode=off` forzados en staging y
  development.
- El secret `pgbackrest_r2_credentials`, `pgbackrest.conf` y su `.example`.
- Los targets `stanza-init` y **`restore-password`**. Este último existía porque el
  restore de pgBackRest es físico y copia el cluster entero, roles y contraseñas
  incluidas: el rol `odoo` sembrado se quedaba con la clave del stack de origen. Un dump
  lógico no tiene ese problema.
- El invariante de dos archivos entre la retención de `backup.sh` y la de
  `pgbackrest.conf`.
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

### Consistencia entre base y filestore

Los adjuntos viven partidos: la fila en la base, el archivo en el filestore. **Un
restore desalineado es la falla silenciosa de este sistema** — la base arranca sana y el
problema aparece meses después, cuando alguien abre un documento viejo.

La decisión de fondo es que **las dos mitades van en el mismo snapshot**. Con eso la
consistencia deja de ser un procedimiento que hay que recordar —respaldar en cierto
orden— y pasa a ser una propiedad del backup: no existe un snapshot con una mitad de una
fecha y la otra de otra.

- **El restore sí tiene orden, y no es simétrico:** primero el filestore, después la
  base. Un filestore más nuevo deja archivos huérfanos, que son inofensivos; uno más
  viejo deja filas apuntando a archivos inexistentes, que es destructivo.
- **El filestore vivo no reemplaza a un snapshot.** El recolector de basura de Odoo
  borra archivos que ninguna fila referencia, así que un estado pasado de la base puede
  referenciar archivos ya limpiados.
- **La verificación lo afirma explícitamente:** el verify del stack comprueba que el
  último snapshot traiga las dos rutas. Un snapshot con el filestore y sin la base
  restaura una base que no existe.

**Respaldar es exclusivo del entorno productivo.** Los otros comparten el repositorio
remoto y los archivos de estado del host, así que la corrida de un entorno descartable
escribiría la marca de éxito que apaga la alerta del real. En prueba eso se garantiza
por composición —su entrypoint le pone `profiles: [restore]` al stack, así que los
timers de backup no se instalan— y por una credencial de R2 de solo lectura.

### El riesgo aceptado: dos copias, no 3-2-1

El diseño entrega la copia viva y una offsite. El escenario no cubierto no es "se rompió
el proveedor" —su durabilidad es alta— sino **perder acceso a la cuenta**: facturación,
suspensión, token revocado. Como el mismo proveedor da el túnel de ingreso y el DNS, ese
evento deja el sistema sin ingreso *y* sin backups el mismo día.

Y hay que decirlo sin adornos: **no hay mitigación efectiva contra el borrado de los
backups.** Un token sin permiso de borrado rompe el diseño, porque la retención necesita
borrar para funcionar; y R2 no soporta versioning de objetos. Quien tenga la credencial
puede vaciar el bucket, y la única defensa real sería una segunda copia en otro
proveedor.

**Descartados:** volcado periódico más cron como único mecanismo (RPO de hasta 24 h, no
cumple el requisito); Duplicati (no aporta nada sobre lo elegido y suma un proceso y una
base de metadata propios); `rclone` como mecanismo de backup en sí (las dos herramientas
ya suben nativo a S3-compatible).

---

## Observabilidad

Se evalúa herramienta por herramienta, no como stack cerrado.

**Prometheus y Grafana: sí.** Lo que se busca es ver tendencias históricas —si la
memoria viene subiendo hace días o fue un pico— y no solo el estado actual. Sin Grafana,
ese histórico solo se consulta con queries manuales, lo que contradice el motivo de
sumar Prometheus.

**Colectores de host, de contenedores y de la base: sí, pero no como contenedores
separados.** Un único agente los embebe como componentes nativos: son los mismos
colectores, con los mismos nombres de métrica, así que los dashboards prearmados siguen
sirviendo. Es el principio de "verificar si algo ya elegido cubre la necesidad" aplicado
**antes** de sumar tres contenedores, no después. Los tres se complementan: el de host
da el total, el de contenedores desglosa cuál servicio consume, y el de la base responde
el *por qué* detrás de ese *cuánto*.

**Logs centralizados: sí.** Se prioriza tenerlos buscables junto a las métricas por
sobre el ahorro de un par de contenedores. El mismo agente que recolecta métricas los
envía; el agente de logs que tradicionalmente cumplía ese rol está descontinuado y su
sucesor es justamente ese agente único.

**La topología es híbrida, y no por gusto.** Consolidar en un agente único crea un punto
ciego: si todo se empuja por él, su muerte no dispara ninguna alerta — las series dejan
de llegar, y un umbral sobre una serie ausente no alerta nada. Entonces Prometheus
scrapea por pull todo lo que ya expone HTTP —incluido el propio agente— y el agente solo
empuja lo que ningún pull alcanza: host, contenedores, base y logs.

**Rol de monitoreo propio en la base.** El exporter usa un rol de solo lectura con
secret propio, no la credencial de la aplicación: el contenedor que tiene el socket de
Docker y el stream de logs de todo el stack no debe portar una credencial de
superusuario.

**Rotación de logs como default del daemon.** Un techo por contenedor —tamaño por
archivo y cantidad de archivos— configurado en el daemon y no en cada servicio: así
cubre todo contenedor presente y futuro sin repetir el bloque en cada módulo de compose.
El techo se elige por la **ventana de recuperación ante un almacén de logs caído**, no
por ahorrar disco: el agente relee de esos archivos, así que cuanto más chicos, menos
historia se recupera. Nota de formato: ese archivo no admite comentarios y el daemon
**rechaza cualquier clave desconocida y no arranca**, así que la justificación vive acá
y el archivo solo lleva las dos opciones reales.

**Retención con dos techos.** Uno por tiempo y otro por tamaño. El segundo es el
fusible: no depende de que la estimación de cardinalidad sea correcta, que es
justamente lo que suele fallar. Riesgo aparte que la retención no cubre: un incidente de
logging descontrolado puede generar en horas volúmenes muy por encima del peor
escenario sostenido — eso se ataja con rotación a nivel del daemon de Docker, no con la
retención del almacén.

**Métricas de capa de aplicación.** Ninguno de los colectores de infraestructura las
captura. El mecanismo son las métricas nativas del reverse proxy —latencia y códigos de
estado por router y servicio, cero contenedor nuevo y cero código de aplicación— más
consultas sobre los logs de la aplicación. Un módulo dedicado daría un desglose más
limpio por tipo de request, pero se difiere mientras no exista para la versión en uso:
portarlo mete trabajo de código de aplicación, de alcance no acotado y con deuda de
rebase permanente, en un repositorio que es puro-infra.

**Lo que queda sin cubrir, explícito:** el desglose de latencia por tipo de request y el
conteo de long-polling. El proxy ve routers, no semántica de la aplicación. Y **Odoo
devuelve 200 incluso ante errores de aplicación**, porque los envuelve en el payload
JSON-RPC — así que la tasa de 5xx medida en el proxy detecta caídas del backend, no
errores funcionales.

**Monitoreo de cron: decisión consciente de no sumar nada.** Se investigaron módulos
pagos, heartbeats de la comunidad y queries propias en el exporter, y se concluyó que la
cobertura actual alcanza. Un hallazgo pesó en la decisión: ni el hosting oficial
gestionado expone tracking de fallo por job individual — solo consumo agregado por
categoría. Se revisita si en la práctica un job falla en silencio y genera un problema
real.

**Alerting nativo de Grafana**, no un componente separado: soporta consultas sobre
métricas y sobre logs por igual, en el mismo lugar donde ya viven los dashboards, y cero
contenedor nuevo. Sin esto, todo el stack de observabilidad sería pasivo — dashboards
que hay que abrir a mano, contradiciendo el objetivo de detectar caídas rápido.

**Provisioning como código.** Datasources, dashboards y recursos de alerting se definen
como archivos versionados junto al resto de la infraestructura. Resuelve el riesgo de
perderlos si el contenedor se recrea, sin necesidad de un backup aparte. Consecuencia
asumida: quedan de solo lectura en la UI, y un cambio se hace editando el archivo.

**Los umbrales de las alertas van literales, y no es un pendiente.** Grafana no ofrece
mecanismo para parametrizarlos: el provisioning de alerting es YAML plano, sin la
interpolación que sí tienen datasources y dashboards. Se probaron las dos formas contra
la imagen del stack: `${VAR}` dentro de `params` ni siquiera parsea (`did not find
expected ',' or ']'`, y la regla entera no se provisiona), y `"$__env{VAR}"` pasa como
cadena literal a un campo que espera un número. Como el valor vive en el archivo de
config de la herramienta, la regla del stack aplica sin excepción: si no se puede
parametrizar por el mecanismo de esa herramienta, se versiona literal. El único umbral
que se cruza con el de otro archivo —el de «backup viejo» contra `RESTIC_MAX_AGE`, fijo
en `stacks/backup/compose.yaml`— lo verifica `make alloy-verify`, que es el stack dueño
de que la alerta avise antes de que el healthcheck marque rojo.

---

## Secretos

**Mecanismo: `secrets:` nativo de Compose**, archivos montados, no variables de entorno.
Una env var queda visible en texto plano vía `docker inspect` y `docker exec … env` —
vector obvio para cualquiera que pueda ejecutar comandos en el contenedor. El mecanismo
nativo evita ambos sin sumar dependencias.

Los valores viven como archivos planos en un directorio excluido de git, con permisos
`640` y el grupo del GID que los consume. El `600` no sirve: Compose fuera de Swarm
ignora `uid`/`gid`/`mode` para secrets de archivo, así que un `600` root-owned rompe la
lectura de cualquier contenedor no-root.

**Descartado un secrets manager dedicado.** A esta escala sería sumar una pieza más
corriendo, con su propio unsealing y su propio backup, para proteger algo que ya se
protege razonablemente con archivos y permisos correctos.

**Una excepción, acotada y escrita:** la credencial de git con la que el servidor clona
los módulos no es un secret de Compose. Al clonar en el host, **ningún contenedor la
consume**, así que vive en el credential store del sistema. Es de solo lectura porque el
servidor nunca escribe en un repo de addons.

**El backup de los secretos va aparte** del pipeline usado para el resto de los datos:
si el servidor se pierde por completo, hace falta ese directorio para redesplegar.
Respaldo manual y separado, no automatizado ni mezclado con los backups operativos.

---

## Gestión

**UI de gestión con privilegio sobre el socket de Docker: no. CLI y `Makefile` en su
lugar.**

Una UI de ese tipo requiere el socket, que es privilegio equivalente a root sobre el
host si el contenedor se compromete. Es superficie de ataque real, no "un contenedor
más". Se evaluaron dos mitigaciones de red y ninguna elimina el riesgo de fondo: si la
UI tiene hostname público para poder usarla como cualquier servicio web, su propio login
queda como la única puerta. La visibilidad que daría ya está cubierta por el stack de
observabilidad, y el proxy aporta su propio dashboard de ruteo.

Esto no prohíbe montar el socket `:ro` para descubrimiento u observación, que es un caso
distinto: lo prohibido es una UI con privilegio sobre él.

**Actualizaciones automáticas: no.** Un upgrade de versión exige leer release notes y
probar antes de aplicarse, ni siquiera en modo "solo notificar". La actualización es un
acto deliberado del operador.

### Escaneo de vulnerabilidades

**A mano cuando el operador quiera mirar, sin target de `Makefile` ni script
versionado.** Se construyó la versión automatizada, se probó contra el stack real, y no
sobrevivió a la evidencia:

- **El resultado no cambia la acción.** Comparar dos tags consecutivos de la imagen
  oficial dio una reducción grande de hallazgos y **ninguno nuevo** — la conclusión fue
  adoptar, que era la conclusión *antes* de escanear. Un tag con fecha existe justamente
  para juntar parches de upstream, y sobre imágenes pineadas la única palanca es subir
  el tag. La asimetría es estructural: quedarse deja **más** CVEs conocidos, no menos,
  porque se acumulan contra una versión fija.
- **Donde sí hay decisión real, el escáner no manda.** En un salto de versión mayor la
  decisión la dominan compatibilidad, migración de esquema y port de los módulos. El
  delta de CVEs es una nota al pie.
- **Instalado no es alcanzable, y el escáner no puede saber la diferencia.** Es un
  inventariador con una base de datos: lee los paquetes instalados y los cruza contra un
  catálogo. No ejecuta nada ni conoce la configuración. Los hallazgos se concentran en
  el intérprete y la libc, presentes en toda imagen del planeta, o en herramientas de
  build que en el contenedor corriendo nunca procesan input de un atacante.
- **El contexto es lo que lo vuelve de bajo valor.** En un pipeline con varios servicios
  y varias personas commiteando, un escáner es genuinamente valioso: detecta lo que
  nadie miró. Con un operador, imágenes upstream pineadas y updates deliberados de a
  uno, casi todo lo que aporta ya lo aporta que el operador revise cada cambio.
- **Descartados también un gate por severidad y un archivo de excepciones.** Sin gate no
  hay nada que silenciar, y registrar la excepción para uno mismo es ceremonia, no
  revisión.

## Redes de Docker

**Tres redes por función:** `edge` (el túnel, el proxy, el emisor de certificados y el
almacén de métricas, que necesita alcanzarlos por pull), `app` (aplicación, base,
backup, el proxy como puente y el agente de observabilidad, que entra a alcanzar la
base) y `observability` (métricas, logs, dashboards y el agente).

Reduce el radio de impacto si un contenedor se compromete, con un mecanismo nativo de
Compose y sin herramienta nueva. Dos consecuencias que un boceto ingenuo de tres redes
no prevé: el almacén de métricas necesita membresía en `edge`, porque la topología
híbrida lo obliga a scrapear el proxy y el túnel por pull directo; y el servicio de DNS
local no está en ninguna red de Docker, porque corre en `network_mode: host`.

## Usuario en runtime

Contrapartida escrita del principio de correr como no-root: se registra quién no lo
cumple y por qué, en vez de darlo por hecho.

| Servicio | Corre como | Por qué |
|---|---|---|
| DNS local | root | Bindea el `53`, puerto privilegiado, en `network_mode: host` |
| Base de datos | root → usuario propio | La imagen oficial arranca root y baja de usuario en su propio entrypoint |
| Aplicación | usuario propio | Cumple sin excepción |
| Restore del filestore | root | Un volumen recién creado nace `root:root`: un no-root no puede crear ahí ni el primer directorio, y solo root le devuelve a cada archivo el owner del snapshot |

---

## Entornos

Un **entorno** es una combinación de tres cosas: un checkout del repositorio, un nombre
de proyecto de Compose, y el entrypoint de `envs/` que elige qué stacks entran. Cambiar
cualquiera de las tres da un entorno distinto.

**Un entorno por checkout.** Cuál es lo dice el `.env` del checkout, no la ruta de un
archivo. No existe `config/production/` ni ningún otro subdirectorio por entorno: los
stacks quedan idénticos en forma, sin excepciones. Se descartó el subdirectorio por
entorno dentro de cada stack: superpone dos aislamientos —el del checkout y el de la
ruta— y el resultado es uno que no aísla nada, por el mismo motivo que el árbol de
addons es uno por checkout.

Los entrypoints **difieren en composición**, porque la naturaleza de cada entorno es
distinta:

|                    | Producción                | Prueba                  | Development             |
|--------------------|---------------------------|-------------------------|-------------------------|
| Naturaleza | Datos reales. Todo resguardado y monitoreado. | Sandbox controlado: validar features antes de producción. | Construcción de módulos e ideas. Servidor o máquina del desarrollador. |
| Dónde corre        | Servidor                  | Servidor                | Máquina del operador    |
| Checkout           | propio                    | propio                  | uno por feature         |
| Nombre de proyecto | `production`              | `staging`               | `development-<feature>` |
| Entrypoint         | `envs/production.yaml`    | `envs/staging.yaml`     | `envs/development.yaml` |
| Rama de addons     | default del Dockerfile    | `<versión>-stag`        | `feat/*`                |
| Proxy              | nginx con TLS, en la LAN  | nginx con TLS, en loopback  | nginx sin TLS, loopback |
| Túnel y certbot    | sí                        | sí                      | no                      |
| DNS local          | solo con servidor local   | no                      | no                      |
| Respalda           | sí                        | **no**, solo restaura   | no                      |
| Observabilidad     | sí                        | no                      | no                      |
| Secrets            | 9                         | 7                       | 2, los dos generados    |

Prueba no lleva observabilidad. Sí lleva `backup`, porque se siembra restaurando el
snapshot de producción y respaldar y restaurar son ahora el mismo contenedor. Desarrollo
lleva `nginx`, `postgres` y `odoo`.

**Que prueba no respalde es estructural, no una omisión.** Su entrypoint le pone
`profiles: [restore]` al stack `backup`, así que queda fuera de la composición por
defecto — y `timers.sh`, que deriva las units de ahí, no instala los timers de backup.
Sin eso, un `sudo make up-timers` en prueba dejaría una corrida nocturna escribiendo en
el repositorio de producción y apagando su alerta de backup viejo. `compose run` alcanza
igual al servicio con el perfil inactivo, así que restaurar funciona sin activar nada.

### Que prueba no respalde, con el contenedor fusionado

Mientras `backup` y `restore` eran dos servicios, la garantía era estructural por
ausencia: prueba no incluía `backup`, así que no había config que pudiera equivocarse.
Fusionarlos tiene ese costo, y la garantía se reconstruye en dos capas, ninguna de las
cuales es "un archivo bien completado":

- **El camino automático** lo da el timer de systemd, que se instala solo en
  producción. Sin timer, el contenedor de prueba no respalda nunca por su cuenta: se
  queda esperando a que alguien le pida un restore.
- **El camino manual** —un `make backup-run` tipeado en el checkout equivocado— lo corta
  la credencial: el token de R2 de prueba es **de solo lectura**. El restore funciona;
  la escritura falla en el proveedor, no en un `if`. Es la misma regla de tokens
  acotados al permiso mínimo que el stack ya aplica en todos lados, y es verificable: la
  verificación de prueba puede afirmar que ese token no puede escribir.

Es más débil que "el servicio no existe" y conviene decirlo así. A cambio, elimina la
duplicación del repositorio de restic en dos stacks y deja una sola herramienta de
respaldos. Se descartó incluir todos los stacks en los tres entornos y apagar `backup`
con `profiles`: convierte una garantía estructural en un archivo bien completado. La
regla que separa los dos mecanismos está en «Cuándo `profiles` y cuándo composición» —
no es una excepción, depende de qué pasa cuando algo se activa por accidente.

Producción y prueba conviven en un servidor. No colisionan porque el `:80` y el `:443`
de la LAN los tiene producción, y prueba publica en loopback —`127.0.0.1:8080` y
`:8443`—, alcanzable por túnel SSH. El ingreso público de prueba no pasa por ahí: entra
por el túnel, que llega a nginx por nombre dentro de su red.

El entrypoint no solo elige stacks: también **ajusta los que eligió**, con `!reset` y
`!override` al lado del `include:` que los trajo. Es la pieza que permite que un stack
sirva a tres entornos sin llevar un solo condicional adentro.

### Cuatro niveles de compartición

No todo se comparte del mismo modo cuando dos entornos conviven en el mismo servidor
—el caso real de producción y prueba. El nivel decide si conviven o se pisan.

**1. Archivos versionados — compartidos por definición.** Todo lo que está en git es el
mismo archivo para todo checkout que salga de ese commit. Cambiarlo para uno lo cambia
para todos. Los `compose.yaml`, los entrypoints, los scripts y el `Makefile` entran acá:
el operador no los toca.

**2. Config real por checkout — no compartido, y por eso divergen.** Cada `.example` se
bootstrapea con `cp` a un archivo real gitignoreado. Dos checkouts en el mismo servidor
tienen su propio `stacks/nginx/config/server-tls.conf`, su propio `postgresql.conf` y su
propio `.env`. **Ahí es donde los entornos difieren de verdad**, y por eso ninguno de
esos valores está parametrizado en el compose. El caso peligroso es copiar el `.env` de
un checkout a otro: se lleva `COMPOSE_PROJECT_NAME`, y con él los volúmenes. Contra eso
no hay mecanismo — solo la advertencia en cada plantilla.

**3. Recursos de Docker con alcance de proyecto — no compartidos.** Contenedores,
volúmenes, redes y tags de imagen derivan de `COMPOSE_PROJECT_NAME`. Dos entornos con
nombres distintos no se ven entre sí, ni siquiera para los datos. El nombre de una
imagen **sí es global al daemon**: por eso cada stack declara
`image: local/<nombre>:${COMPOSE_PROJECT_NAME}`. Con un tag fijo, el `build` de un
entorno pisaría la imagen que corre el otro, sin avisar.

**4. Recursos globales al host — compartidos siempre.** Acá está lo que colisiona:

| Recurso | Quién lo toma | Qué pasa con un segundo entorno |
|---|---|---|
| `:80` y `:443` de la LAN | nginx de producción | prueba publica en `127.0.0.1:8080`/`:8443`, y development en `:8081` |
| `:53` en `network_mode: host` | dnsmasq | no admite un segundo de ninguna forma — por eso prueba **no lo incluye**, y no alcanza con no activarle el perfil |
| `:3001` de la UI de Grafana | grafana de producción | prueba no lleva observabilidad |
| units de systemd | las de cada checkout | van prefijadas con el nombre del proyecto, así que no se pisan |
| `/etc/docker/daemon.json` | el daemon | uno solo para todo el host; lo instala `make host-init` |
| repositorio de restic en R2 | producción escribe | prueba **lee**: mismo repositorio, credencial de solo lectura |

### Lo que la observabilidad de producción ve

Alloy monta el socket de Docker y `/rootfs`, así que **mide el host entero**: sus
métricas de contenedores incluyen los de prueba, y sus logs también. Es deliberado — un
contenedor que se reinicia en loop importa venga del entorno que venga.

Lo que no cruza es la base: el exporter de Postgres apunta a `postgres` por nombre
dentro de la red `app` de su propio proyecto, así que solo ve la suya.

---

## Ciclo de vida: cómo se levanta un Odoo funcional

Nueve bloques, en orden, cada uno con su propia verificación ejecutable. El comando
exacto de cada paso está en [`docs/entorno/levantar-produccion.md`](docs/entorno/levantar-produccion.md)
(los tres entornos usan los mismos bloques); acá solo el mapa:

| # | Bloque | Deja |
|---|---|---|
| 1 | Prerrequisitos | Cuentas de terceros (DNS, túnel, SMTP, storage de backup) y el host con Docker listo |
| 2 | Repositorio | `.env`, los secrets cargados, el daemon rotando logs |
| 3 | Edge | Certificado, reverse proxy, túnel de ingreso y DNS de la LAN |
| 4 | Database | Postgres corriendo con su tuning |
| 5 | **Addons** | `addons/addons.txt` completado, `make repo-sync` trajo el árbol de módulos, la imagen construida |
| 6 | Odoo | La aplicación sirviendo por el hostname público, sobre ese árbol |
| 7 | Backup | Snapshot probado de punta a punta, avisando por mail si falla |
| 8 | Monitoring | Métricas, logs y alertas |
| 9 | Cierre | El stack entero convergiendo de una sola vez |

El bloque 5 es la bisagra entre la infraestructura y los repositorios de módulos: es
donde el manifiesto deja de ser una lista y se convierte en el árbol que el bloque 6
necesita para arrancar — el entrypoint de Odoo aborta si el `addons_path` queda vacío.

---

## Scripts

Cada stack trae los scripts que operan ese stack — `postgres/verify.sh`,
`backup/backup.sh`. Arriba quedan solo los transversales: `secrets-init.sh` y
`config-init.sh` bootstrapean lo gitignoreado desde su `.example` —el primero pregunta
qué secret declara la composición, el segundo qué stack está activo—, `addons.sh`, y un
`verify` que **orquesta**: corre el de cada stack presente y junta resultados, sin saber
qué espera ninguno.

Cambia el dueño único de las verificaciones, no lo elimina: pasa de un archivo que sabe
qué se espera de todas las piezas, a un dueño por stack, más chico y al lado de lo que
describe. Agregar un stack deja de tocar el verificador global.

## Acoplamientos que ninguna forma de árbol disuelve

`prometheus` y `alloy` scrapean por nombre de contenedor, y `nginx` rutea a `odoo` por
nombre. Son acoplamientos de naturaleza, no de forma: separarlos en carpetas no los
desacopla, solo los esconde detrás de un `../`.

## Decisiones abiertas y pendientes

**Frecuencia del snapshot.** Diario es el default de Odoo.sh y el punto de partida
razonable. Cuál es el RPO tolerable para un deployment concreto es del operador.

**El resolver de la LAN no lo decide este repositorio.** `dnsmasq` resuelve el hostname
para quien le pregunte, pero quién le pregunta lo reparte el DHCP del router. Es un
prerrequisito escrito en [`docs/entorno/configurar-dhcp-dns-lan.md`](docs/entorno/configurar-dhcp-dns-lan.md),
un `dig` sin `@` desde un equipo de la LAN, y un `omitir` explícito en el verify de
dnsmasq que dice que desde el servidor no se puede verificar. **Sigue sin haber
mecanismo**, porque no lo hay del lado del stack — lo que hay es que dejó de dar verde
por accidente.

**El workflow de CI sigue sin poder existir.** Hay una suite de `make test` más
`bash -n` listos para correr en cada push, y ningún lugar donde correrlos: es una
decisión pendiente sobre dónde vive el repositorio, no trabajo técnico pendiente.

---

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
│   │   │   └── odoo.conf            ← versionado tal cual, sin .example: SMTP llega
│   │   │                               por env, nada más queda por deployment
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
│   │   └── verify.sh
│   │
│   ├── certbot/                 ← profiles: [cert] — one-off, pero con todo lo suyo
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile
│   │   ├── scripts/wrapper.sh   ← bind-mount, no COPY: es runtime, no build
│   │   ├── systemd/cert-renew.{service,timer}
│   │   └── verify.sh
│   │
│   ├── cloudflared/             ← sin config/: el túnel entra por secret, no por archivo
│   │   ├── compose.yaml
│   │   ├── image/Dockerfile
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
│   │       cada uno: compose.yaml · image/Dockerfile · config/ (versionado tal cual,
│   │       sin valores por deployment) · verify.sh
│   │
├── scripts/                     ← solo lo transversal
│   ├── verify-stacks.sh         ← orquesta: corre el de cada stack presente
│   ├── verify-host.sh           ← lo que es del SO, no de ningún stack
│   ├── secrets-init.sh · secrets-perms.sh · config-init.sh
│   ├── addons.sh · pydeps.sh · integrity-check.sh · failure-notify.sh
│   ├── timers.sh
│   └── lib/{ui.sh,verify.sh,compose.sh}
│
├── host/
│   ├── daemon.json              ← rotación de logs, global al daemon
│   └── systemd/notify@.service  ← transversal: la usan los timers de cualquier stack
│
├── secrets/                     ← gitignoreado
├── addons/                      ← gitignoreado por contenido
├── tests/
└── docs/                        ← manual de procedimientos, ver README.md
```

### Adentro de un stack: `image/`, `config/`, `scripts/`

Tres carpetas, mismo criterio en las once: **por qué existe el archivo, no qué tipo de
archivo es**.

- **`image/`** — lo que participa del build: el `Dockerfile` y todo lo que ese
  `Dockerfile` hace `COPY` (el `entrypoint.sh` de `odoo` vive ahí, al lado, no en
  `scripts/`, porque se copia adentro de la imagen).
- **`config/`** — lo que la herramienta lee en runtime: `.example` versionado, real
  gitignoreado al lado.
- **`scripts/`** — lo que un humano o un timer invocan desde el host, sin pasar por el
  build: `backup.sh` de backup, `wrapper.sh` de certbot. No existe si el stack no tiene
  nada así.

`compose.yaml` se queda en la raíz del stack, nunca adentro de una subcarpeta: es lo que
`envs/*.yaml` nombra por `include:`, y ese camino tiene que ser predecible sin mirar
adentro de cada stack.

**Todo stack tiene `image/Dockerfile`, incluso sin nada que agregarle a la imagen
oficial.** `postgres` y `nginx` son casos así: dos líneas, un `FROM` pineado y nada más.
Es deliberado — la alternativa es `image: postgres:17.10` directo en el compose, sin
build, que dice exactamente lo mismo en una línea y sin capa extra. El costo real: dejar
de pullear el tag oficial y pasar a construir sobre él en cada checkout, y `make up`
sobre un checkout nuevo necesita un `build` antes del primer `up` para los once stacks,
no solo para los que de verdad compilan algo. Se paga a cambio de que ningún stack sea
la excepción — el día que `postgres` necesite algo instalado, es una línea en un archivo
que ya existe, no una carpeta nueva.

### Lo que hace que esto se lea solo

**Todos los stacks están a la misma profundidad.** `stacks/<nombre>/`, sin excepción.
Por eso la ruta de un stack a cualquier cosa compartida es siempre `../../`, idéntica en
los once — no hay que contar carpetas.

**El nombre del stack es el nombre del contenedor.** No hay traducción entre lo que
decís (`make grafana-logs`), lo que ves (`stacks/grafana/`) y lo que corre.

**Los `.example` viven al lado de su archivo real.** El bootstrap es siempre el mismo
gesto en la misma carpeta, y una verificación puede afirmar que ningún `.example` quedó
sin copiar sin saber nada de cada herramienta.

**Los timers viven con su stack.** `cert-renew` con certbot, los de backup con backup:
un stack trae todo lo suyo, incluido lo que se instala fuera del checkout. Es lo que
hace que `timers.sh` derive qué units corresponden preguntándole a la composición — la
carpeta dueña de la unit es el servicio que la habilita. Arriba queda solo
`notify@.service`, que cualquier timer usa.

**Ningún stack tiene `.env` propio.** Es la regla de configuración funcionando: los tags
van pineados literales en el compose, lo que Compose sí interpola —puertos, nombres—
sale del `.env` de la raíz vía el entrypoint del entorno, y lo demás vive en el config
de su herramienta. El único `env_file:` del repositorio es el de `backup`, y no es un
`.env` de stack sino `config/r2.env`: las credenciales de R2 en el formato que restic
parsea.
