# Roadmap de construcción

**Las siete etapas están cumplidas.** El árbol que describe
[modular-architecture.md](modular-architecture.md) —once stacks bajo `stacks/`, un
entrypoint por entorno en `envs/`— está escrito, probado y corriendo. Este documento
queda como registro de en qué orden se construyó y por qué ese orden: sirve para entender
decisiones, no para saber qué falta.

**No fue una migración, fue una construcción.** No había ningún deployment corriendo, así
que no hubo datos que proteger, ni cutover, ni vuelta atrás que preparar. Las piezas que
el diseño descarta —pgbouncer, pgBackRest, `restore-db`, los agregadores por capa— no se
desmontaron: **nunca se escribieron**.

## El principio de ordenamiento

**El orden lo dictó qué se podía probar corriendo, no qué era riesgoso.**

Desarrollo son tres stacks —`postgres`, `odoo`, `nginx`— y corre en la máquina del
desarrollador. Es el entorno más chico que existe y el único que se puede levantar sin un
servidor, así que **se construyó primero y entero**: con eso quedaron probados `include:`,
el bootstrap de configs con `cp` y los targets del `Makefile`. Los ocho stacks restantes
copiaron un patrón ya demostrado en vez de estrenarlo.

De ahí salió el resto del orden: cada etapa agregó los stacks que hacían falta para que el
siguiente entorno levantara, y terminó cuando ese entorno levantó de verdad.

---

## Etapa 1 — Desarrollo levanta ✅

El esqueleto y los tres stacks que lo componen.

- `envs/development.yaml`: redes, secrets y los tres `include:`.
- Cada stack con su `image/Dockerfile` y su `config/`, aunque no compile nada propio —
  ver [modular-architecture.md](modular-architecture.md#adentro-de-un-stack-image-config-scripts).
- `stacks/postgres/` — `image/Dockerfile` es solo `FROM postgres:17.10`.
  `config/postgresql.conf` con su `.example`, sin `archive_mode`.
- `stacks/odoo/` — `image/{Dockerfile,entrypoint.sh}`, `config/odoo.conf` con
  `db_maxconn = 15` y sin `bus_alt_connection`. Apunta a `postgres:5432`.
- `stacks/nginx/` — `image/Dockerfile` es solo `FROM nginx:1.31.3-alpine`.
  `config/server-plain.conf` versionado, publicando `127.0.0.1:8080`.
- Los targets `<stack>-up/down/logs/ps` del `Makefile` pasan a derivarse de la composición.

**Verificación, y fue real porque corre local.** `make up` levanta los tres, Odoo responde
en el 8080 a través de nginx, se crea una base y se instala un módulo.

Fue la etapa que **probó los mecanismos**: que las rutas relativas resuelvan contra la
carpeta de cada archivo incluido, y que un config real bootstrapeado con `cp` se monte
donde corresponde. Si algo de eso no funcionaba, se descubría acá y no con nueve stacks
escritos encima. El `env_file` por stack se probó también y **no sobrevivió al diseño
final**: ningún stack terminó necesitando uno propio, salvo `backup` para las credenciales
de R2.

## Etapa 2 — La verificación por stack ✅

Sobre los tres que ya corren, para fijar el patrón antes de repetirlo.

- `stacks/<nombre>/verify.sh`, dueño de qué se espera de ese stack.
- `scripts/verify-stacks.sh` pasa a orquestar: corre el de cada stack presente y junta
  resultados, sin saber qué espera ninguno. Lo que es del SO y no de ningún stack queda
  aparte, en `scripts/verify-host.sh`.
- `tests/` sigue el corte, con los stubs por stack.

**Verificación.** `make verify` con desarrollo arriba, y con desarrollo abajo — los dos
casos, porque el modo de falla conocido de este script es dar `ok` cuando no hay nada que
mirar. Mutá una aserción y comprobá que **falla**.

## Etapa 3 — El borde completo ✅

Lo que le falta a `envs/production.yaml` para servir tráfico.

- `stacks/cloudflared/`.
- `stacks/certbot/` como stack propio, con su unit de renovación. Se evaluó dejarlo
  adentro de `nginx` por ser un one-off; tiene imagen, secret, script, unit y chequeos
  propios, así que el principio se refinó — ver
  [modular-architecture.md](modular-architecture.md#la-unidad-un-stack--un-contenedor-con-cosas-propias).
- `stacks/dnsmasq/` con `profiles: [lan]`, y `COMPOSE_PROFILES` en las plantillas de `.env`.
- Los configs de nginx que sí varían por deployment: `00-http.conf`, `server-tls.conf`,
  `odoo.locations`, cada uno con su `.example`.

**Verificación.** `docker compose config --services` con y sin `COMPOSE_PROFILES=lan`
devuelve composiciones distintas. Emisión del certificado por DNS-01. El rate-limit del
login responde con 429 al superar el umbral.

## Etapa 4 — Respaldos ✅

Snapshot desde el primer día: no hay estrategia previa que reemplazar.

- `stacks/backup/` — un contenedor restic declarado `100:101`, con `backup.sh` y
  `restore.sh` al lado, y sus dos units de systemd.
- El dump y el filestore van **en el mismo snapshot**. El dump sin comprimir, o restic
  deja de deduplicar.
- El restore se invoca con `docker compose run --user 0:0`.
- El aviso cuando el tiempo del dump cruza el umbral tolerable.

**Verificación.** Un backup completo y **un restore que devuelve una base usable con
adjuntos que abren**. Un backup que no se probó restaurando no cuenta como etapa cumplida.

## Etapa 5 — Observabilidad ✅

Los cuatro stacks, que son los que menos dependen de todo lo demás.

- `stacks/prometheus/` · `stacks/loki/` · `stacks/grafana/` · `stacks/alloy/`, cada uno
  con su config y su `verify.sh`.
- Datasources, dashboards y alerting como código.

**Verificación.** Alloy resuelve sus referencias **ejecutándose** y leyendo su API:
`alloy validate` acepta constantes inexistentes con exit 0. Las series de host,
contenedores y base llegan; una alerta de prueba sale al canal.

## Etapa 6 — Prueba ✅

El entrypoint que faltaba, y lo único que ese entorno necesita de propio.

- `envs/staging.yaml`: sin observabilidad, nginx con `ports: !reset []`, Odoo con
  `ODOO_DISABLE_SMTP`.
- Lleva `backup`, porque respaldar y restaurar son el mismo contenedor. Que no respalde lo
  sostienen el timer —que se instala solo en producción— y **un token de R2 de solo
  lectura**.

**Verificación.** Sembrar prueba desde el snapshot de otro checkout. `make backup-run` ahí
**falla en el proveedor**, no en un `if`.

## Etapa 7 — Limpieza ✅

- Desaparece `docker/`.
- Se borra el aviso de migración de `CLAUDE.md`.
- `docs/stacks.md` describe el estado nuevo.
- Los runbooks dejan de nombrar rutas que ya no existen, y el de PITR deja de existir.

**Verificación.** Ninguna ruta nombrada en la documentación apunta a algo inexistente.
`make test` y `make verify` en verde sin ningún archivo bajo `docker/`.

---

## Después de la etapa 7

Las siete etapas cerraron con el árbol escrito y `make test` en verde, pero **ninguna lo
había corrido contra un servidor de verdad**. Eso pasó después, y encontró cosas que
`docker compose config` no puede encontrar:

- **El shakedown del primer deploy real.** Siete hallazgos, cada uno con su causa y su
  verificación: la guarda de `daemon.json` que no mostraba contra qué, un comentario
  permanente que contaba como placeholder sin reemplazar, un endpoint de R2 sin sufijo que
  fallaba a los 66 s en vez de a 1 s, cuatro claves que la plantilla de `.env` nunca
  declaró, y cuatro runbooks que prometían targets borrados con `docker/`.
- **SMTP con una sola fuente.** `smtp_server`/`port`/`user` dejaron de estar pegados a mano
  en tres archivos y pasan por `.env` al entrypoint, que los appendea al conf de runtime.
  Con eso `odoo.conf` y `grafana.ini` dejaron de necesitar `.example`.

La disciplina que sostuvo las siete etapas es la que encontró estas: **una etapa termina
cuando algo levanta y responde**, no cuando el código está escrito. `make verify` ya había
encontrado una vez que la mitad de sus propios `ok` mentían con los servicios abajo —
cualquier verificación no ejecutada puede estar mintiendo, y correrla contra hardware real
sigue siendo la única forma de saberlo.

## Lo que cambió respecto del plan anterior

| Plan de migración | Plan de construcción |
|---|---|
| Sacar pgbouncer con verificación en tres entornos | No se escribió |
| Correr el snapshot en paralelo antes de sacar pgBackRest | pgBackRest no existió nunca |
| Diff normalizado de la config resuelta | No aplicó: no había config previa que preservar |
| Orden por riesgo, producción al final | Orden por qué se podía probar corriendo |
| Vuelta atrás por etapa | No había nada a lo que volver |
