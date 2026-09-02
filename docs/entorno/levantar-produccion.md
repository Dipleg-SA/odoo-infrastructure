# Levantar producción

## Cuándo se usa

Puesta en marcha de un deploy de producción nuevo — desde el repositorio clonado hasta el sistema listo para recibir el primer dato real de un usuario.

Los tres entornos se levantan con los **mismos bloques y los mismos comandos**. Lo que cambia es qué stacks trae cada entorno, y eso lo dice su entrypoint: `make nginx-up` levanta lo mismo en los tres, pero producción además tiene `certbot`, `cloudflared` y la observabilidad. Para el segundo y el tercer stack sobre este mismo servidor, ver [levantar-staging](levantar-staging.md) y [levantar-desarrollo](levantar-desarrollo.md).

## Objetivo

Los once stacks resueltos, cada uno verificado, con el certificado real, los backups probados una vez de punta a punta y las alertas llegando por mail. El deploy termina en el primer dato que carga un usuario — todo lo anterior es descartable.

| Bloque | Acá | |
|---|---|---|
| 1 · Prerrequisitos | cuentas de terceros y el host listo | ✓ |
| 2 · Repositorio | `.env` y los 9 secrets cargados | ✓ |
| 3 · Edge | certificado, túnel y DNS de la LAN | ✓ |
| 4 · Database | la base corriendo y ya respaldándose | ✓ |
| 5 · Addons | el árbol de módulos y la imagen | ✓ |
| 6 · Odoo | el sitio sirviendo por el hostname | ✓ |
| 7 · Backup | las dos mitades corriendo y avisando | ✓ |
| 8 · Monitoring | métricas, logs y las siete alertas | ✓ |
| 9 · Cierre | el stack convergiendo de una sola vez | ✓ |

El orden no es negociable: cada bloque depende de que el anterior haya cerrado, y las tres inversiones que parecen raras —el certificado antes que el proxy, el archivado antes del primer dato, los addons antes que Odoo— están explicadas donde ocurren.

---

## 1 · Prerrequisitos

**Objetivo** — todo lo anterior al primer `git clone`: cuentas de terceros y configuración de sistema operativo, cada una con su runbook y su verificación.

**Las tres primeras van en ese orden y son el camino crítico**: la delegación de la zona puede tardar 48h, el Tunnel necesita la zona ya creada y ZeptoMail verifica su dominio contra esa misma zona. Las otras tres son independientes entre sí y de las anteriores.

| Prerrequisito | Runbook | Te deja |
|---|---|---|
| Zona de Cloudflare + token de API | [crear-zona-cloudflare](crear-zona-cloudflare.md) | `secrets/cloudflare_api_token` |
| Tunnel de Cloudflare | [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md) | `secrets/cloudflare_tunnel_token` |
| ZeptoMail | [configurar-zeptomail](configurar-zeptomail.md) | `secrets/zeptomail_smtp_password` · `SMTP_USER` · `SMTP_HOST` · `ALERT_EMAIL_FROM` · `ALERT_EMAIL_TO` |
| Bucket de R2 + credenciales | [crear-bucket-r2](crear-bucket-r2.md) | `secrets/restic_r2_credentials` · `secrets/restic_password` · el bucket/endpoint van a `stacks/backup/config/r2.env` (bloque 2), no a `.env` |
| Token de git de solo lectura | [crear-token-git-lectura](crear-token-git-lectura.md) | `~/.git-credentials` del servidor |
| Docker Engine y Compose, habilitados al arranque | [configurar-docker-host](configurar-docker-host.md) | El host listo para correr el stack |

Los cinco secrets con `CAMBIAR` del bloque 2 salen todos de esta tabla. `make host-verify` confirma la última fila y que cada secret tenga un valor cargado, pero no que ese valor sirva: la zona y ZeptoMail se prueban contra el tercero en su propio runbook, y el token del Tunnel y la clave de R2 recién en los bloques 3 y 4, la primera vez que algo los usa.

Dos cosas que parecen prerrequisitos y no lo son, porque necesitan el repositorio clonado: la **rotación de logs del daemon**, que es `sudo make host-init` en el bloque 2 —antes del primer contenedor—, y el **DNS/DHCP de la LAN**, que va en el bloque 3 ([configurar-dhcp-dns-lan](configurar-dhcp-dns-lan.md)). De la segunda conviene traer decidida la IP LAN que va a reservar el router.

---

## 2 · Repositorio

**Objetivo** — el repo clonado en el último release, con `.env` y los 9 secrets cargados y validados, y el daemon de Docker ya rotando logs. Nada levantado todavía.

**A mano** — `.env.production.example` deja cinco claves vacías y explica cada una donde se edita; no hay una segunda lista acá. Dos salen directo de los prerrequisitos (`SMTP_USER`, `ALERT_EMAIL_FROM`); `LOCAL_IP` sale del segundo comando de abajo; `PUBLIC_HOSTNAME` y `ALERT_EMAIL_TO` se completan a mano. `SMTP_HOST` ya viene cargada con el host fijo de ZeptoMail —no hay que tocarla—. La trampa real es `LOCAL_IP`: tiene que ser una IP real de una interfaz existente —`dnsmasq` bindea exactamente ahí y si no, queda `unhealthy`—. Ninguna puede quedar vacía **ni ausente**: `host-verify` cruza contra `.env.production.example` y marca las dos cosas — Compose interpola una variable vacía sin fallar y el síntoma aparece capas después. El bucket y el endpoint de R2 **no** van acá: se editan directo en `r2.env`, más abajo en este mismo bloque, apenas `config-init` lo bootstrapea.

`secrets-init` deja **9 archivos**: 4 generados que no se tocan nunca y 5 con el marcador `CAMBIAR`, que se llenan con los valores de los prerrequisitos. Cuántos son sale de la composición, no de esta lista — un stack sin observabilidad declara menos. Tres detalles de formato:

- `cloudflare_api_token`: sin comillas y **sin salto de línea final** — `nano -L`. Cloudflare emite dos formatos según cuándo lo creaste: 40 caracteres el viejo, `cfut_...` (~46) el nuevo — los dos son válidos.
- `restic_r2_credentials` ya viene con su esqueleto en el formato de AWS, que es lo que restic parsea (ver [rotar-credenciales-r2](../credenciales/rotar-credenciales-r2.md)).
- Editor interactivo, nunca `echo >>`: así ningún token queda en el historial de la shell.

```bash
git clone git@github.com:tu-organizacion/odoo-infrastructure.git odoo-production && cd odoo-production
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

Al último tag, no al `HEAD` de la rama por defecto: `HEAD` detached es un guard-rail contra corregir código en el servidor.

```bash
cp .env.production.example .env
echo "LAN:     $(hostname -I | awk '{print $1}')"
echo "Pública: $(curl -s ifconfig.me)"
nano .env
```

`LAN` va a `LOCAL_IP` y tiene que caer en tu subred local: si sale una IP de tu VPN o de un bridge de Docker, agarró la interfaz equivocada. Anotá además la IP por la que administrás el servidor —la de tu VPN—: la usan los dos túneles SSH del apéndice.

```bash
make secrets-init
nano -L secrets/cloudflare_api_token   # -L: sin salto de línea final
nano secrets/cloudflare_tunnel_token
nano secrets/zeptomail_smtp_password
nano secrets/restic_r2_credentials
nano secrets/restic_password
```

`secrets-init` imprime cuáles quedaron con `CAMBIAR`, y es idempotente: nunca pisa un valor ya cargado. Los dos de R2 traen su esqueleto INI — se completan los valores, no se reemplaza el archivo.

```bash
sudo make secrets-perms
set -a; . ./.env; set +a
```

`secrets-perms` deja cada archivo en `640` con el grupo del proceso no-root que lo lee, y necesita root porque `chgrp` a un GID ajeno lo exige. El `set -a` carga `.env` en **esta** shell: si abrís una terminal nueva, repetilo.

```bash
make config-init
```

Bootstrapea de una sola vez los config reales de los stacks que todavía los necesitan desde su `.example`. `postgresql.conf`, `00-http.conf` y `odoo.locations` sirven tal cual; `odoo.conf`, `grafana.ini` y `contact-points.yaml` ya no bootstrapean nada —SMTP y el destinatario de alertas llegan por `.env`, no se editan a mano en ningún archivo—; quedan tres con un placeholder real:

```bash
nano stacks/nginx/config/server-tls.conf       # TU_DOMINIO → PUBLIC_HOSTNAME (4 apariciones)
# Solo si este stack lleva LAN (COMPOSE_PROFILES=lan en tu .env):
nano stacks/dnsmasq/config/dnsmasq.conf        # TU_DOMINIO → PUBLIC_HOSTNAME, TU_IP_LOCAL → LOCAL_IP
nano stacks/backup/config/r2.env               # TU_ENDPOINT y TU_BUCKET, del prerrequisito de R2
```

Sin LAN activo, `dnsmasq.conf` no lo bootstrapeó `config-init` recién —`servicios_activos` lo filtra por su `profiles: [lan]`— y ese `nano` abriría un archivo vacío en vez de la plantilla.

Todos los valores son los mismos que ya cargaste en `.env`, salvo los de R2: esos van directo a `r2.env`, nunca a `.env` (ver bloque 1).

```bash
sudo make host-init
```

**Va acá porque el bloque 3 crea el primer contenedor.** El driver de logging se fija al crear cada contenedor, no al arrancarlo: aplicarlo después no alcanza con reiniciar el daemon, obliga a recrear los once. `dockerd` no arranca si `daemon.json` tiene claves desconocidas, comentarios simulados incluidos; si el restart falla, `journalctl -u docker` trae el motivo exacto.

```bash
make host-verify
```

Cubre versión de Compose, arranque automático de Docker, la rotación de logs recién aplicada, `.env` sin claves vacías, la identidad declarada del stack, permisos y GID de los 9 secrets, y la superficie publicada del host.

---

## 3 · Edge

**Objetivo** — el certificado emitido, nginx sirviendo con él, el Tunnel conectado y `dnsmasq` resolviendo el hostname a la IP local para la LAN.

**A mano** — el Tunnel y su Public Hostname ya quedaron configurados en [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md); `server-tls.conf` y `dnsmasq.conf` ya los bootstrapeaste y editaste en el bloque 2. `00-http.conf` y `odoo.locations` ya traen valores razonables (rate-limit, CIDR de Docker); tocalos solo si tu LAN cae en `172.16.0.0/12`.

```bash
make cert-issue && make nginx-up
make cloudflared-up
# Solo si este stack lleva LAN (COMPOSE_PROFILES=lan en tu .env):
make dnsmasq-up
```

**El orden importa y es al revés de lo intuitivo: primero el certificado, después el proxy.** nginx no arranca si el archivo del certificado no existe, y con DNS-01 certbot no necesita que nginx esté vivo para emitirlo — valida contra la API de Cloudflare, no contra el puerto 80. Por eso son dos comandos encadenados y no `make up`.

`cloudflared` y `dnsmasq` van en líneas propias y no encadenados con `&&`: ninguno de los dos depende del certificado ni de que nginx haya arrancado. **Corré la línea de `dnsmasq` solo si tu `.env` tiene `COMPOSE_PROFILES=lan` descomentado** — medido: nombrarlo explícito en `up`/`run` salta el filtro de `profiles:` aunque el perfil esté inactivo, así que en un VPS sin LAN no falla con "no such service" como parecería razonable esperar. Lo que pasa en cambio depende de si `dnsmasq.conf` ya existe: si LAN nunca estuvo activo en este checkout, `config-init` nunca lo bootstrapeó, Docker monta un directorio vacío en su lugar y el contenedor no llega a arrancar —reintenta en loop, molesto pero inofensivo, el `53` nunca se bindea—; si el archivo sí quedó de una activación anterior, arranca de verdad con `network_mode: host` y queda escuchando en `${LOCAL_IP}:53` sin que lo hayas pedido.

**El hostname público va a dar 502 al terminar este bloque, y está bien.** nginx ya sirve con el certificado real, pero su upstream —Odoo— no existe hasta el bloque 6.

```bash
make nginx-verify
make certbot-verify
make cloudflared-verify
# Solo si este stack lleva LAN:
make dnsmasq-verify
```

`nginx-verify` cubre el servicio `healthy`, que la config renderizada no tenga variables sin sustituir, que el `server_name` sea tu hostname, que el `proxy_pass` vaya por variable con el resolver de Docker declarado, las tres rutas de Odoo y que la cadena nginx → Odoo responda de verdad, el log de nginx sin errores y los binds. Los días que le quedan al certificado, el timer de renovación y el token de la API de Cloudflare los cubre `certbot-verify`, aparte; las conexiones del Tunnel las cubre `cloudflared-verify` — nginx no sabe nada de ninguno de los dos.

El timer todavía no existe: lo instala `sudo make up-timers` en el bloque 7, junto con los de backup. Es el único chequeo de `certbot-verify` que queda rojo hasta entonces.

nginx no publica ninguna UI: su estado se lee del log (JSON, `make nginx-logs`) y de `make nginx-verify`. Los dos chequeos que no se pueden correr en el servidor están en el apéndice.

---

## 4 · Database

**Objetivo** — la base corriendo, con su config real y su presupuesto de conexiones coherente.

**A mano** — nada: `postgresql.conf` ya lo bootstrapeó `config-init` en el bloque 2, y no necesita edición. Los valores de tuning son ratios sobre el `mem_limit` del contenedor, no sobre la RAM del host. Si bajás ese cap, revisá la tabla entera —se calcularon juntos—, no la fila que parece afectada.

```bash
make postgres-up
```

El rol `odoo` y su password son **definitivos**: el bloque 6 reusa esa misma credencial sin rotarla.

```bash
make postgres-verify
```

Cubre el servicio `healthy`, que acepte conexiones, los logs sin errores de permisos, que el puerto no esté publicado, y que las conexiones que Odoo puede abrir —`db_maxconn` por sus procesos— entren en `max_connections`. **Sin pooler, pasarse no encola: Postgres rechaza.** Los dos valores viven en archivos de herramientas distintas y nada más los ata.

---

## 5 · Addons

**Objetivo** — el árbol de módulos en disco y la imagen de Odoo construida. El bloque 6 no arranca sin esto: el entrypoint aborta si el `addons_path` queda vacío.

**A mano** — completar `addons/addons.txt`, que `config-init` ya bootstrapeó en el bloque 2, con tus repos, uno por línea (`URL categoría`). Si no tenés ninguno todavía, podés dejarlo vacío y volver después (ver [gestionar-fork § Crear](../modulos/gestionar-fork.md#crear)).

```bash
nano addons/addons.txt
```

```bash
make repo-sync && make build
```

El token de git de solo lectura ya tiene que estar en `~/.git-credentials` — lo piden los repos privados del manifiesto, los forks públicos no.

**El build no clona nada.** Instala las dependencias Python de `addons/requirements.txt` si el archivo existe —lo escribe `make addons-deps`— y copia el entrypoint, nada más. La consecuencia buscada: desplegar un cambio de módulo no vuelve a requerir un rebuild.

```bash
make repo-status
```

Encabeza con la rama declarada y sigue con una fila por repo del manifiesto, todas en `limpio`. Un `(sin worktree)` o un `sucio` es un sync incompleto. Si un repo privado falló con `Repository not found` o `Authentication failed`, al token le faltan permisos: alcanza con lectura de contenidos sobre tu organización. Un `huérfano: categoría/nombre` al final es un directorio que quedó en disco después de sacarlo del manifiesto — `repo-sync` no lo borra solo. Es un chequeo visual — `make odoo-verify` lo vuelve a validar mecánicamente en el bloque siguiente.

---

## 6 · Odoo

**Objetivo** — Odoo sirviendo por el hostname público con certificado propio. Acá se cierra el 502 que dejó el bloque 3.

**A mano** — nada: `smtp_server`/`port`/`user` los toma el entrypoint de `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER` en `.env`, que ya cargaste en el bloque 2. `odoo.conf` no tiene nada que editar.

**Y la contraseña de `admin`, apenas el sitio responda y antes que cualquier otra cosa.** El `-i base` del primer arranque la deja en `admin`, y para ese momento el sitio ya está publicado en internet por el Tunnel. Entrá a `https://$PUBLIC_HOSTNAME` → Ajustes → Usuarios → `admin` → cambiar contraseña. Es distinta del **master password** (`admin_passwd`), que se gestiona vía `secrets:` y no se toca acá.

```bash
make odoo-up && make odoo-logs
```

El entrypoint detecta que la base está vacía y corre `-i base --stop-after-init` con la conexión explícita a `postgres:5432`, antes de que el entrypoint oficial arme su propia espera. Esperá `HTTP service (werkzeug) running` y cortá los logs con Ctrl-C.

**Ahora cambiá la contraseña de `admin`.** Después, si corresponde instalar módulos, ver [gestionar-modulo](../modulos/gestionar-modulo.md).

```bash
make odoo-verify
```

Cubre el servicio `healthy`, los logs sin errores de permisos, `smtp_server` cargado de verdad en el conf runtime, Odoo respondiendo en su `:8069`, los worktrees limpios, los módulos server-wide presentes en el árbol, la rama de addons coherente con la versión de la imagen, las categorías coherentes entre `addons.sh` y el `addons_path`, y los puertos sin publicar. Las tres rutas de Odoo en nginx las cubre `nginx-verify`, en el bloque 3 — no este comando.

**Y el chatter, con dos sesiones abiertas:** mandá un mensaje y confirmá que aparece solo, sin recargar. Prueba que nginx rutea `/websocket` al worker gevent (`8072`) y que el `LISTEN/NOTIFY` del bus funciona contra la conexión directa a Postgres. Es lo único de este bloque que no se puede automatizar; la cadena pública y el rate-limit están en el apéndice.

---

## 7 · Backup

**Objetivo** — el backup corriendo, probado una vez de punta a punta, y avisando por mail si falla.

**A mano** — nada: `r2.env` ya lo bootstrapeaste y editaste en el bloque 2. Este bloque va después del 6 porque su verificación exige un snapshot, y un snapshot exige que exista un filestore.

```bash
make backup-up
docker compose exec -T backup restic init
sudo make up-timers
```

> **Nunca `restic init --force`.** Sobre un repositorio con backups adentro los deja inaccesibles. No existe el caso en el que haga falta.

`up-timers` deriva de la composición qué units le corresponden a **este** stack —el backup diario, la verificación mensual de integridad y la renovación del certificado— y las instala con el nombre del proyecto adelante (`production-backup-daily.timer`), inyectando la ruta absoluta del checkout. Con eso, un segundo stack en el mismo servidor instala las suyas sin pisar estas. Incluye la unit plantilla de aviso: sin ella, una corrida que falle no avisa.

**En prueba ese comando no instala los timers de backup**, y eso es estructural: su entrypoint le pone `profiles: [restore]` al stack, así que queda fuera de la composición que `timers.sh` consulta.

```bash
make backup-run
```

Hace el dump de la base, lo mete **en el mismo snapshot** que el filestore, y aplica la retención GFS con `forget --prune`. Que las dos mitades vayan juntas es lo que hace que la consistencia sea una propiedad del backup y no un procedimiento que hay que recordar.

```bash
make backup-verify
sudo make notify-test
```

`backup-verify` cubre el servicio `healthy`, que `r2.env` no tenga el placeholder sin reemplazar, que el endpoint termine en `.r2.cloudflarestorage.com`, que el repositorio sea alcanzable con snapshots de este stack, que el último traiga **las dos mitades** del estado, el registro de addons, y los dos timers activos con el nombre de este checkout. Si el contenedor sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora. **No lo recrees para forzarlo** — le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención.

`notify-test` dispara la unit de aviso de verdad. Tiene que dar `Result=success` **y llegar el mail**.

> **Un backup sin probar no es un backup.** Agendá ahora el simulacro de restore semestral — ver [restore-simulacro-semestral](../backup-restore/restore-simulacro-semestral.md), y leelo una vez ahora, con el sistema sano.

---

## 8 · Monitoring

**Objetivo** — métricas de host, contenedores y base, logs centralizados, y las siete alertas vivas **y llegando por mail**.

**A mano** — nada de config: SMTP y el destinatario llegan por `GF_SMTP_*`/`ALERT_EMAIL_TO` desde `.env`, que ya cargaste en el bloque 2 — `grafana.ini` y `contact-points.yaml` no tienen nada que editar. Falta la prueba de entrega de las alertas en la UI de Grafana. El acceso está en el apéndice porque el `3001` solo escucha en loopback.

```bash
make monitoring-role
make prometheus-up && make loki-up && make grafana-up && make alloy-up
```

`monitoring-role` crea el rol de solo lectura que scrapea Postgres, con la clave de `secrets/postgres_exporter_password`. Es propio a propósito: `pg_monitor` da lectura de las vistas de estadísticas y nada más, así que el agente que tiene el socket de Docker y los logs no porta la credencial de la aplicación. El target es repetible —hace `DROP` y `CREATE`—, así que sirve igual para rotar esa clave.

```bash
make prometheus-verify
make loki-verify
make grafana-verify
make alloy-verify
```

Cuatro comandos porque cada stack es dueño de lo suyo. `prometheus-verify` cubre el servicio `healthy`, que ningún target esté caído, y las tres familias de métricas que empuja Alloy. `loki-verify` cubre que reciba logs de verdad, etiquetados por contenedor —consultado desde Prometheus, porque Loki no publica puerto—. `grafana-verify` cubre el servicio `healthy`, **las siete reglas de alerting realmente cargadas** —lo que promete el Objetivo de este bloque— y que SMTP y el destinatario no hayan quedado con alguna clave vacía. `alloy-verify` cubre que sus componentes internos resuelvan de verdad —`alloy validate` no alcanza, acepta referencias inexistentes con exit 0— y que la alerta de backup avise antes de que el healthcheck se ponga rojo. Los binds de los cuatro se verifican en su propio script.

`loki` es el único servicio sin `(healthy)` y es correcto: su imagen es distroless estricta. Su caída la cubre `up == 0` en Prometheus, que lo scrapea directo.

---

## 9 · Cierre

**Objetivo** — el sistema listo para recibir datos, con todo lo que los protege ya corriendo **y ya probado una vez**. El punto de no retorno real no es el `-i base` del bloque 6 —esa base es descartable— sino el primer dato que carga un usuario.

**A mano** — el cuarto y último consumidor de SMTP: que **Odoo** mande un mail propio, distinto de los tres anteriores (`notify-test`, Grafana y el `curl` de emisión). Disparar una notificación saliente —invitar un usuario alcanza— y confirmar que llega.

```bash
make up
```

Los bloques anteriores levantaron capa por capa. Este `make up` es la primera vez que corre la cadena entera sin argumentos, y confirma que converge sola.

```bash
make verify
```

Tienen que quedar corriendo **nueve servicios** —diez si tu `.env` tiene LAN activo— y **ninguno** del perfil `restore`. `certbot` no cuenta: corre con `--rm` y nunca queda arriba, así que sumaría un stack más al total de once pero no un servicio corriendo.

- [ ] `make verify` sale con exit `0`
- [ ] La contraseña de `admin` ya no es `admin`
- [ ] Odoo mandó un mail propio y llegó
- [ ] Hay un snapshot de restic con las dos mitades del estado, de la corrida del bloque 7
- [ ] Llegó el mail de prueba del contact point de Grafana
- [ ] Los chequeos del apéndice están hechos
- [ ] El simulacro de restore semestral está agendado y leído una vez
- [ ] Las dos passphrases de cifrado están en el gestor de contraseñas, **fuera del servidor**

La última no es ceremonia: es lo único de esta lista que, si falta, no se puede arreglar después.

A partir de acá, la operación normal está repartida en [operacion/](../operacion/), [modulos/](../modulos/), [backup-restore/](../backup-restore/) y [credenciales/](../credenciales/).

---

## Apéndice — lo que no se corre en el servidor

Tres chequeos que el servidor no puede hacerse a sí mismo, más uno que es al revés. Los tres primeros van juntos para no ir y volver de máquina: el primer grupo desde otro equipo de la LAN, el segundo desde fuera de la LAN (datos móviles alcanza), el tercero desde la máquina con la que administrás. El cuarto —el rate-limit, más abajo— hay que corrérselo al servidor a sí mismo, porque desde afuera la latencia de Cloudflare esconde el corte.

```bash
HOST_PUB='el-hostname-publico'; SRV_LAN='ip-lan-del-servidor'
echo "dnsmasq responde:"; dig +short "$HOST_PUB" @"$SRV_LAN"
echo "la LAN le pregunta:"; dig +short "$HOST_PUB"
for p in 5432 6432; do nc -z -w2 "$SRV_LAN" "$p" && echo "MAL: $p alcanzable" || echo "OK: $p inalcanzable"; done
```

**El que importa es el segundo `dig`.** Si el primero da la IP local y el segundo devuelve una IP de Cloudflare, `dnsmasq` está sano y no lo usa nadie: quién resuelve para la LAN lo decide el DHCP del router, no este repositorio — ver [configurar-dhcp-dns-lan](configurar-dhcp-dns-lan.md). Los dos puertos de la base no tienen que existir hacia afuera.

```bash
SRV_PUB='ip-publica-del-servidor'; HOST_PUB='el-hostname-publico'
nc -z -w2 "$SRV_PUB" 443 && echo "MAL: el router está reenviando el 443" || echo "OK: sin reenvío"
curl -sI "https://$HOST_PUB/web/login" | grep -iE "^HTTP|^server:|^cf-ray:"
```

El ingreso entra por el túnel, así que el 443 del router no tiene que estar reenviado. Y del `curl` tienen que salir **los tres headers**: solo Cloudflare agrega `server:` y `cf-ray:`, y un `200` sin ellos significa que el pedido nunca salió a internet. Corre desde afuera y no desde el servidor porque ahí `dnsmasq` resolvería al nginx local y daría `200` **aunque el Tunnel esté roto**. Si da 502, confirmá el Origin Server Name — ver [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md).

```bash
SRV_ADMIN='ip-de-administracion-del-servidor'
ssh -N -L 3001:127.0.0.1:3001 "<usuario>@$SRV_ADMIN"
```

Con el túnel abierto, `http://localhost:3001`. Usuario `admin`, contraseña en `secrets/grafana_admin_password`. Adentro tienen que estar los **5 dashboards** y las **7 reglas de alerta**, provisionadas y de solo lectura. **Y que las alertas lleguen:** Alertas → Contact points → `email-operador` → **Test**, y el mail tiene que llegar a la dirección de `contact-points.yaml` (la misma que `ALERT_EMAIL_TO`). Si no llega, revisá en orden: saldo de créditos, remitente verificado, y `docker compose logs grafana | grep -i smtp`. Si el `ssh` responde `Permission denied (publickey)`, mirá a qué IP fue: un `127.0.0.1` ahí significa que lo estás corriendo en el servidor contra sí mismo.

El rate-limit del login se prueba una sola vez, en el servidor, y va acá porque deja el login en 503 unos segundos:

```bash
for i in $(seq 1 20); do curl -sk -o /dev/null -w "%{http_code} " -X POST \
  --resolve "$PUBLIC_HOSTNAME:443:$LOCAL_IP" "https://$PUBLIC_HOSTNAME/web/login"; done; echo
```

El `400` es Odoo rechazando un POST sin token CSRF — válido, no un fallo; lo que se mide es el corte en el 11.º, que `limit_req` devuelve como 503. Va directo a nginx por `--resolve` a propósito: con la latencia de Cloudflare de por medio el corte no aparece nunca.
