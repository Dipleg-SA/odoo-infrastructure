# Roadmap de construcción

Plan para escribir el árbol que describe [modular-architecture.md](modular-architecture.md):
once stacks bajo `stacks/`, un entrypoint por entorno en `envs/`.

**No es una migración, es una construcción.** No hay ningún deployment corriendo, así que
no hay datos que proteger, ni cutover, ni vuelta atrás que preparar. Las piezas que el
diseño descarta —pgbouncer, pgBackRest, `restore-db`, los agregadores por capa— no se
desmontan: **nunca se escriben**. Lo que queda bajo `docker/` es material de referencia
hasta que el árbol nuevo esté completo, y se borra de una en la última etapa.

## El principio de ordenamiento

**El orden lo dicta qué se puede probar corriendo, no qué es riesgoso.**

Desarrollo son tres stacks —`postgres`, `odoo`, `nginx`— y corre en la máquina del
desarrollador. Es el entorno más chico que existe y el único que se puede levantar sin un
servidor, así que **se construye primero y entero**: con eso quedan probados `include:`,
el `env_file` por stack, el bootstrap de configs con `cp` y los targets del `Makefile`.
Los siete stacks restantes copian un patrón ya demostrado en vez de estrenarlo.

De ahí sale el resto del orden: cada etapa agrega los stacks que hacen falta para que el
siguiente entorno levante, y termina cuando ese entorno levanta de verdad.

Durante la construcción conviven los dos árboles. Es deliberado y temporal: `make test`
sigue resolviendo los entrypoints viejos mientras los nuevos aparecen, y el aviso al tope
de `CLAUDE.md` dice cuál es cuál.

---

## Etapa 1 — Desarrollo levanta

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

**Verificación, y es real porque corre local.** `make up` levanta los tres, Odoo responde
en el 8080 a través de nginx, se crea una base y se instala un módulo. `make test` en
verde con los cuatro entrypoints —los tres viejos y el nuevo—.

Es la etapa que **prueba los mecanismos**: que cada stack lea su propio `.env`, que las
rutas relativas resuelvan contra la carpeta de cada archivo incluido, y que un config
real bootstrapeado con `cp` se monte donde corresponde. Si algo de eso no funciona, se
descubre acá y no con nueve stacks escritos encima.

## Etapa 2 — La verificación por stack

Sobre los tres que ya corren, para fijar el patrón antes de repetirlo.

- `stacks/<nombre>/verify.sh`, dueño de qué se espera de ese stack.
- `scripts/verify.sh` pasa a orquestar: corre el de cada stack presente y junta
  resultados, sin saber qué espera ninguno.
- `tests/` sigue el corte, con los stubs por stack.

**Verificación.** `make verify` con desarrollo arriba, y con desarrollo abajo — los dos
casos, porque el modo de falla conocido de este script es dar `ok` cuando no hay nada que
mirar. Mutá una aserción y comprobá que **falla**.

## Etapa 3 — El borde completo

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

## Etapa 4 — Respaldos

Snapshot desde el primer día: no hay estrategia previa que reemplazar.

- `stacks/backup/` — un contenedor restic declarado `100:101`, con `backup.sh` y
  `restore.sh` al lado, y sus dos units de systemd.
- El dump y el filestore van **en el mismo snapshot**. El dump sin comprimir, o restic
  deja de deduplicar.
- El restore se invoca con `docker compose run --user 0:0`.
- El aviso cuando el tiempo del dump cruza el umbral tolerable.

**Verificación.** Un backup completo y **un restore que devuelve una base usable con
adjuntos que abren**. Un backup que no se probó restaurando no cuenta como etapa cumplida.

## Etapa 5 — Observabilidad

Los cuatro stacks, que son los que menos dependen de todo lo demás.

- `stacks/prometheus/` · `stacks/loki/` · `stacks/grafana/` · `stacks/alloy/`, cada uno
  con su config y su `verify.sh`.
- Datasources, dashboards y alerting como código.

**Verificación.** Alloy resuelve sus referencias **ejecutándose** y leyendo su API:
`alloy validate` acepta constantes inexistentes con exit 0. Las series de host,
contenedores y base llegan; una alerta de prueba sale al canal.

## Etapa 6 — Prueba

El entrypoint que faltaba, y lo único que ese entorno necesita de propio.

- `envs/staging.yaml`: sin observabilidad, nginx con `ports: !reset []`, Odoo con
  `ODOO_DISABLE_SMTP`.
- Lleva `backup`, porque respaldar y restaurar son el mismo contenedor. Que no respalde lo
  sostienen el timer —que se instala solo en producción— y **un token de R2 de solo
  lectura**.

**Verificación.** Sembrar prueba desde el snapshot de otro checkout. `make backup-run` ahí
**falla en el proveedor**, no en un `if`.

## Etapa 7 — Limpieza

- Desaparece `docker/`.
- Se borra el aviso de migración de `CLAUDE.md`.
- `docs/stacks.md` describe el estado nuevo.
- Los runbooks dejan de nombrar rutas que ya no existen, y el de PITR deja de existir.

**Verificación.** Ninguna ruta nombrada en la documentación apunta a algo inexistente.
`make test` y `make verify` en verde sin ningún archivo bajo `docker/`.

---

## Lo que cambió respecto del plan anterior

| Plan de migración | Plan de construcción |
|---|---|
| Sacar pgbouncer con verificación en tres entornos | No se escribe |
| Correr el snapshot en paralelo antes de sacar pgBackRest | pgBackRest no existe nunca |
| Diff normalizado de la config resuelta | No aplica: no hay config previa que preservar |
| Orden por riesgo, producción al final | Orden por qué se puede probar corriendo |
| Vuelta atrás por etapa | No hay nada a lo que volver |

Lo único que sobrevive intacto es la disciplina de verificación: **cada etapa termina
cuando algo levanta y responde**, no cuando el código está escrito. `make verify` ya
encontró una vez que la mitad de sus propios `ok` mentían con los servicios abajo; asumí
que cualquier verificación no ejecutada puede estar mintiendo.
