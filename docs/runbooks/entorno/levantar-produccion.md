# Levantar producción

## Cuándo se usa

Puesta en marcha de un deploy de producción nuevo — desde el repositorio clonado, con los prerrequisitos ya resueltos, hasta el sistema listo para recibir el primer dato real de un usuario. Ocho fases, en orden: cada una depende de que la anterior haya cerrado.

Para levantar un segundo entorno sobre un stack de producción ya operativo, ver [levantar-staging](levantar-staging.md) y [levantar-desarrollo](levantar-desarrollo.md) — los dos reusan buena parte de lo que se decide acá (identidad del stack, secrets, addons) pero son procedimientos propios, no continuaciones de este.

## Objetivo

Once servicios corriendo, verificados capa por capa, con el certificado real, los backups probados una vez de punta a punta y las alertas llegando por mail. El deploy termina en el primer dato que carga un usuario — todo lo anterior es descartable.

## Prerrequisitos

Todo esto es anterior al primer `git clone` de este procedimiento: cuentas de terceros y configuración de sistema operativo, cada una con su propio runbook y su propia verificación. **Las tres primeras van en ese orden y son el camino crítico**: la delegación de la zona puede tardar 48h, el Tunnel necesita la zona ya creada y ZeptoMail verifica su dominio contra esa misma zona. Las otras tres son independientes entre sí y de las anteriores.

| Prerrequisito | Runbook | Te deja |
|---|---|---|
| Zona de Cloudflare + token de API | [crear-zona-cloudflare](crear-zona-cloudflare.md) | `secrets/cloudflare_api_token` |
| Tunnel de Cloudflare | [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md) | `secrets/cloudflare_tunnel_token` |
| ZeptoMail | [configurar-zeptomail](configurar-zeptomail.md) | `secrets/zeptomail_smtp_password` · `SMTP_USER` · `ALERT_EMAIL_FROM` |
| Bucket de R2 + credenciales | [crear-bucket-r2](crear-bucket-r2.md) | `secrets/pgbackrest_r2_credentials` · `secrets/restic_r2_credentials` · `secrets/restic_password` · `R2_ENDPOINT` · `R2_BUCKET` |
| Token de git de solo lectura | [crear-token-git-lectura](crear-token-git-lectura.md) | `~/.git-credentials` del servidor |
| Docker Engine y Compose, habilitados al arranque | [configurar-docker-host](configurar-docker-host.md) | El host listo para correr el stack |

Los seis secrets con `CAMBIAR` de la fase 1 salen todos de esta tabla. `make host-verify` confirma la última fila y que cada secret tenga un valor cargado, pero no que ese valor sirva: la zona de Cloudflare y ZeptoMail se prueban contra el tercero en su propio runbook, y el token del Tunnel y la clave de R2 recién en las fases 2 y 3, la primera vez que algo los usa.

Dos cosas que parecen prerrequisitos y no lo son, porque necesitan el repositorio clonado: la **rotación de logs del daemon**, que es el paso 7 de la fase 1 —antes del primer contenedor—, y el **DNS/DHCP de la LAN**, que va en la fase 2 ([configurar-dhcp-dns-lan](configurar-dhcp-dns-lan.md)). De la segunda conviene igual traer decidida la IP LAN que va a reservar el router.

---

## Fase 1 — El repositorio

### Objetivo

El repo clonado en el último release, con `.env` y los 11 secrets cargados y validados, y el daemon de Docker ya rotando logs. Nada levantado todavía.

### A mano

`secrets-init` deja **11 archivos**: 5 generados que no se tocan nunca —`postgres_password`, `pgbouncer_credentials`, `odoo_admin_password`, `grafana_admin_password`, `postgres_exporter_password`— y 6 con el marcador `CAMBIAR`, que se llenan con los valores que ya conseguiste en los prerrequisitos. Tres detalles de formato:

- `cloudflare_api_token`: sin comillas y **sin salto de línea final** — `nano -L`. Cloudflare emite dos formatos según cuándo lo creaste: 40 caracteres el viejo, `cfut_...` (~46) el nuevo — los dos son válidos.
- `pgbackrest_r2_credentials` y `restic_r2_credentials` ya vienen con su esqueleto INI. **La misma clave de R2 va en los dos**, en sintaxis distinta: al rotarla hay que tocar ambos (ver [rotar-credenciales-r2](../credenciales/rotar-credenciales-r2.md)).
- Editor interactivo, nunca `echo >>`: así el token no queda en el historial.

En `.env`, seis claves más. Cuatro salen directo de los prerrequisitos (`R2_ENDPOINT`, `R2_BUCKET`, `SMTP_USER`, `ALERT_EMAIL_FROM`); las otras dos se completan acá:

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | Nombre del stack: `production` acá. Gobierna contenedores, volúmenes, redes y tags de imagen |
| `COMPOSE_FILE` | `docker/compose.yaml` para producción |
| `PUBLIC_HOSTNAME` | El hostname público de esta instancia, el mismo que configuraste en el Tunnel |
| `LOCAL_IP` | La IP LAN del servidor — real y de una interfaz existente: `dnsmasq` bindea exactamente ahí y si no, queda `unhealthy` |
| `PGBACKREST_STANZA` | Nombre de la stanza, estable — cambiarlo deja huérfanos los backups viejos |
| `ALERT_EMAIL_TO` | Destinatario de los avisos de backup y de las alertas de Grafana |

### Comandos

```bash
echo "# 1 → Completá la URL de tu fork"
REPO_URL='git@github.com:tu-organizacion/odoo-infrastructure.git'
```

```bash
echo "# 2 → Clonar y fijar al último release"
git clone "$REPO_URL" && cd "$(basename "$REPO_URL" .git)"
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

Al último tag, no al `HEAD` de la rama por defecto: `HEAD` detached es un guard-rail contra corregir código en el servidor.

```bash
echo "# 3 → Esqueleto de config y secrets"
cp .env.prod.example .env
make secrets-init
```

`secrets-init` imprime cuáles quedaron con `CAMBIAR`, y es idempotente: nunca pisa un valor ya cargado.

```bash
echo "# 4 → IPs del servidor — anotá las dos primeras, las piden las fases 2 y 5"
echo "LAN:     $(hostname -I | awk '{print $1}')"
echo "Pública: $(curl -s ifconfig.me)"
```

`LAN` va a `LOCAL_IP` y tiene que caer en tu subred local: si sale una IP de tu VPN o de un bridge de Docker, agarró la interfaz equivocada. Anotá además la IP por la que administrás el servidor — la de tu VPN —, que la usan los túneles SSH de las fases 2 y 7.

Cargá los valores de arriba. Después:

```bash
echo "# 5 → Permisos y grupo de cada secret"
sudo make secrets-perms
```

Deja cada archivo en `640` con el grupo del proceso no-root que lo lee. Necesita root porque `chgrp` a un GID ajeno lo exige.

```bash
echo "# 6 → Cargar .env en la shell — repetilo en cada sesión nueva"
set -a; . ./.env; set +a
echo "OK: PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME · LOCAL_IP=$LOCAL_IP"
```

De acá en adelante los comandos usan esas variables en vez de valores literales. Si abrís una terminal nueva, volvé a correr este bloque.

```bash
echo "# 7 → Rotación de logs del daemon — el último momento para aplicarla"
sudo cp config/docker/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker
```

**Va acá porque la fase 2 crea el primer contenedor.** El driver de logging se fija al crear cada contenedor, no al arrancarlo: aplicarla después no alcanza con reiniciar el daemon, obliga a recrear los once — ver [contenedor-no-rota-logs](../troubleshooting/observability/contenedor-no-rota-logs.md).

`dockerd` no arranca si `daemon.json` tiene claves desconocidas, comentarios simulados incluidos. Si el restart falla, `journalctl -u docker` trae el motivo exacto.

### Verificación

```bash
echo "# 8 → Prerrequisitos del servidor y config del repo"
make host-verify
```

Cubre versión de Compose, arranque automático de Docker, la rotación de logs recién aplicada, `.env` sin claves vacías, la identidad declarada del stack, permisos y GID de los 11 secrets, y la superficie publicada del host.

---

## Fase 2 — Borde

### Objetivo

El certificado emitido, nginx sirviendo con él, el Tunnel conectado —ya configurado como prerrequisito— y `dnsmasq` resolviendo el hostname a la IP local para la LAN.

**El orden importa y es al revés de lo intuitivo: primero el certificado, después el proxy.** nginx no arranca si el archivo del certificado no existe, y con DNS-01 certbot no necesita que nginx esté vivo para emitirlo — valida contra la API de Cloudflare, no contra el puerto 80.

### A mano

Ninguno — el Tunnel y su Public Hostname ya quedaron configurados en [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md).

### Comandos

```bash
echo "# 1 → Emitir el certificado (one-off; nginx todavía no existe)"
make cert-issue
```

```bash
echo "# 2 → Levantar el borde (dnsmasq se construye la primera vez)"
docker compose up -d cloudflared nginx dnsmasq
```

**El hostname público va a dar 502 al terminar esta fase, y está bien.** nginx ya sirve con el certificado real, pero su upstream —Odoo— no existe hasta la fase 5.

### Verificación

```bash
echo "# 3 → Estado del borde"
make edge-verify
```

Cubre los tres servicios `healthy`, que la config renderizada no tenga variables sin sustituir, que el `server_name` sea tu hostname, que el `proxy_pass` vaya por variable con el resolver de Docker declarado, los días que le quedan al certificado, las conexiones del Tunnel, el log de nginx sin errores, los binds (`80`/`443` en `${LOCAL_IP}`) y el token de Cloudflare.

Dos chequeos no se pueden correr en el servidor:

```bash
echo "# 4 → Desde otro equipo de la LAN: las dos líneas tienen que dar la IP local del servidor"
HOST_PUB='el-hostname-publico'; SRV_LAN='ip-lan-del-servidor'
echo "4a — dnsmasq responde:"; dig +short "$HOST_PUB" @"$SRV_LAN"
echo "4b — la LAN le pregunta:"; dig +short "$HOST_PUB"
```

**El que importa es el 4b.** Si el 4a da la IP local y el 4b devuelve una IP de Cloudflare, `dnsmasq` está sano y no lo usa nadie: quién resuelve para la LAN lo decide el DHCP del router, no este repositorio — ver [configurar-dhcp-dns-lan](configurar-dhcp-dns-lan.md) para dejarlo apuntando ahí.

```bash
echo "# 5 → Desde fuera de la LAN (datos móviles): tiene que fallar"
SRV_PUB='ip-publica-del-servidor'
nc -z -w2 "$SRV_PUB" 443 && echo "MAL: el router está reenviando el 443" || echo "OK: sin reenvío"
```

nginx no publica ninguna UI. Su estado se lee del log (JSON, `docker compose logs nginx`) y de `make edge-verify`.

---

## Fase 3 — Datos

### Objetivo

La base corriendo y **ya respaldándose**, antes de que exista un solo dato adentro.

### A mano

Ninguno. La única decisión de esta fase es de orden, explicada abajo.

### Comandos

```bash
echo "# 1 → Levantar la base y el pooler (postgres se construye la primera vez)"
docker compose up -d postgres pgbouncer
```

El rol `odoo` y su password son **definitivos** — la fase 5 reusa esa misma credencial sin rotarla.

```bash
echo "# 2 → Crear la stanza y probar el archivado hasta R2"
docker compose exec -T -u postgres postgres pgbackrest stanza-create
docker compose exec -T -u postgres postgres pgbackrest check && echo "OK: el archive_command llega a R2"
```

**Va acá y no en la fase 6, y la ventana tiene que ser cero.** Postgres arranca con `archive_mode = on`, así que cada archivado falla hasta que la stanza exista y los WAL se acumulan en `pg_wal`. `check` fuerza un switch de WAL y lo sigue hasta R2 — es también donde se prueba por primera vez la credencial de R2. Si falla acá, mirá el endpoint (va sin esquema), el bucket y la clave.

### Verificación

```bash
echo "# 3 → Estado de la capa de datos"
make db-verify
```

Cubre los dos servicios `healthy`, `archive_mode` y `archive_command`, la stanza cifrada en R2, que no haya WAL pendiente, los logs sin errores de permisos, que ningún puerto esté publicado, y la **autenticación real a través de PgBouncer** — `pg_isready` solo pregunta si el puerto responde, así que un `auth_file` ilegible lo pasa igual.

```bash
echo "# 4 → Desde otro equipo de la LAN: ninguno de los dos puertos existe hacia afuera"
SRV_LAN='ip-lan-del-servidor'
for p in 5432 6432; do nc -z -w2 "$SRV_LAN" "$p" && echo "MAL: $p alcanzable" || echo "OK: $p inalcanzable"; done
```

---

## Fase 4 — Addons

### Objetivo

El árbol de módulos en disco y la imagen de Odoo construida. La fase 5 no arranca sin esto: el entrypoint aborta si el `addons_path` queda vacío.

### A mano

`addons/addons.txt` no existe todavía. Se bootstrapea desde su plantilla y se completa con tus repos, uno por línea (`URL categoría`) — al menos el que provee `bus_alt_connection` (obligatorio), aunque no tengas módulos propios todavía; si no tenés ninguno, forkealo primero (ver [crear-fork](../modulos/crear-fork.md)).

### Comandos

```bash
echo "# 1 → Bootstrapear el manifiesto y los pines desde sus plantillas"
cp addons/addons.txt.example addons/addons.txt
cp addons/requirements.txt.example addons/requirements.txt
${EDITOR:-vi} addons/addons.txt
```

```bash
echo "# 2 → Clonar los repos del manifiesto y armar el árbol"
make addons-sync
```

El token de git de solo lectura ya tiene que estar en `~/.git-credentials` — ver [crear-token-git-lectura](crear-token-git-lectura.md). Lo piden los repos privados del manifiesto; los forks públicos no.

```bash
echo "# 3 → Construir la imagen de Odoo"
docker compose build odoo && echo "OK: imagen construida"
```

**El build no clona nada.** Instala las dependencias Python de `addons/requirements.txt` si el archivo existe —lo escribe `make pydeps-sync`, no se versiona— y copia el entrypoint, nada más. La consecuencia buscada: desplegar un cambio de módulo no vuelve a requerir un rebuild.

### Verificación

```bash
echo "# 4 → Estado de cada worktree"
make addons
```

Encabeza con la rama declarada y sigue con una fila por repo del manifiesto, todas en `limpio`. Un `(sin worktree)` o un `sucio` es un sync incompleto. Si un repo privado falló con `Repository not found` o `Authentication failed`, el token no tiene los permisos justos: alcanza con lectura de contenidos sobre tu organización.

Es un chequeo visual: `make odoo-verify` lo vuelve a validar mecánicamente en la fase siguiente.

---

## Fase 5 — Aplicación

### Objetivo

Odoo sirviendo por el hostname público con certificado propio de Let's Encrypt. Acá se cierra el 502 que dejó la fase 2.

### A mano

**La contraseña de `admin`, apenas el sitio responda y antes que cualquier otra cosa.** El `-i base` del primer arranque la deja en `admin`, y para ese momento el sitio ya está publicado en internet por el Tunnel.

Entrá a `https://$PUBLIC_HOSTNAME` → Ajustes → Usuarios → `admin` → cambiar contraseña. Es distinta del **master password** (`admin_passwd`), que se gestiona vía `secrets:` y no se toca acá.

### Comandos

```bash
echo "# 1 → Levantar Odoo (el primer arranque tarda)"
docker compose up -d odoo
docker compose logs -f odoo
```

El entrypoint detecta que la base está vacía y corre `-i base --stop-after-init` conectándose directo a `postgres:5432`, no a PgBouncer: el modo transacción no soporta los advisory locks ni el DDL que necesita una inicialización. Esperá `HTTP service (werkzeug) running` y cortá el `logs -f`.

**Ahora cambiá la contraseña de `admin`.** Después, si corresponde instalar módulos, ver [crear-modulo](../modulos/crear-modulo.md) o [actualizar-modulo](../modulos/actualizar-modulo.md).

`bus_alt_connection` no entra en esa lista: se carga por `server_wide_modules` en `odoo.conf`, no por instalación en la base.

### Verificación

```bash
echo "# 2 → Estado de la aplicación"
make odoo-verify
```

Cubre el servicio `healthy`, los logs sin errores de permisos, Odoo respondiendo en su `:8069`, los worktrees limpios, las tres rutas en la config renderizada de nginx, el gestor de bases deshabilitado, los puertos sin publicar, y el certificado.

Tres cosas quedan a mano:

```bash
echo "# 3 → ¿Por dónde va a salir el pedido? Esto decide si el chequeo 4 vale"
dig +short "$PUBLIC_HOSTNAME"
```

Si devuelve IPs de Cloudflare, el 4 es válido desde el propio servidor. Si devuelve `$LOCAL_IP`, el host está usando `dnsmasq` como resolver: el pedido iría directo a nginx sin pasar por Cloudflare y daría `200` **aunque el Tunnel esté roto**. En ese caso corré el 4 desde otra red.

```bash
echo "# 4 → La cadena pública completa: tienen que salir LOS TRES headers"
curl -sI "https://$PUBLIC_HOSTNAME/web/login" | grep -iE "^HTTP|^server:|^cf-ray:"
```

Solo Cloudflare agrega `server:` y `cf-ray:`. Un `200` sin ellos significa que el pedido nunca salió a internet. Si en cambio da 502, confirmá el Origin Server Name — ver [crear-tunnel-cloudflare](crear-tunnel-cloudflare.md).

```bash
echo "# 5 → Rate-limit del login: diez 400 y después 503"
for i in $(seq 1 20); do curl -sk -o /dev/null -w "%{http_code} " -X POST \
  --resolve "$PUBLIC_HOSTNAME:443:$LOCAL_IP" "https://$PUBLIC_HOSTNAME/web/login"; done; echo
```

El `400` es Odoo rechazando un POST sin token CSRF — válido, no un fallo; lo que se mide es el corte en el 11.º, que `limit_req` devuelve como 503. Va directo a nginx por `--resolve` a propósito: con la latencia de Cloudflare de por medio el corte no aparece nunca.

**Y el chatter, con dos sesiones abiertas:** mandá un mensaje y confirmá que aparece solo, sin recargar. Prueba que nginx rutea `/websocket` al worker gevent (`8072`), y que `bus_alt_connection` está activo — sin él, el modo transacción de PgBouncer rompe el `LISTEN/NOTIFY` del bus.

---

## Fase 6 — Protección

### Objetivo

Las dos mitades del backup corriendo, probadas una vez de punta a punta, y avisando por mail si fallan.

### A mano

Ninguno. Como en la fase 3, lo único propio es el orden: va después de la 5 porque su verificación exige un snapshot, y un snapshot exige que exista un filestore.

### Comandos

```bash
echo "# 1 → Levantar el contenedor de restic e inicializar el repositorio"
docker compose up -d backup
docker compose exec -T backup restic init && echo "OK: repositorio de restic creado"
```

> **Nunca `restic init --force`.** Sobre un repositorio con backups adentro los deja inaccesibles. No existe el caso en el que haga falta.

```bash
echo "# 2 → Units de systemd (la ruta absoluta se inyecta al instalar)"
sudo -v
for u in config/systemd/*.service; do sed "s|CAMBIAR-en-deploy|$(pwd)|g" "$u" | sudo tee "/etc/systemd/system/$(basename "$u")" >/dev/null; done
sudo cp config/systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now odoo-backup-daily.timer odoo-backup-monthly.timer && echo "OK: timers activos"
```

El `sudo -v` adelante no es decorativo: si `sudo` pidiera contraseña en medio del pegado, se comería la línea siguiente como respuesta. El glob incluye `odoo-notify@.service`, la unit plantilla que instancia el `OnFailure=` de las otras dos: sin ella, un backup que falle no avisa.

```bash
echo "# 3 → Primera corrida completa (tarda; ver abajo antes de arrancarla)"
make backup
```

Encadena `pgbackrest check` → `backup --type=diff` → registro de addons → `restic backup` → `forget --prune`. **El orden no es casual:** pgBackRest primero y restic después, siempre.

**Va a parecer trabada y no lo está.** pgBackRest no imprime nada hasta terminar: en una instalación nueva son ~2000 archivos y más de 10 minutos. **No le des Ctrl-C**: un full abortado deja basura parcial. Para ver que avanza, desde otra sesión:

```bash
docker compose exec -T postgres tail -f /var/log/pgbackrest/*-backup.log
```

El primero sale `full` y no `diff`: pgBackRest promueve solo cuando no hay un full previo del cual diferir.

### Verificación

```bash
echo "# 4 → Estado de la capa de protección"
make backups-verify
```

Cubre el snapshot de restic, el full de pgBackRest, el registro de addons, los dos timers activos, el `OnFailure=` cableado, y que ningún contenedor del perfil `restore` esté corriendo.

Si el contenedor sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora. **No lo recrees para forzarlo** — le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención.

```bash
echo "# 5 → El aviso de fallo, de punta a punta"
sudo systemctl start odoo-notify@prueba.service
systemctl is-active odoo-notify@prueba.service; systemctl show -p Result --value odoo-notify@prueba.service
```

Tiene que dar `Result=success` **y llegar el mail**.

> **Un backup sin probar no es un backup.** Agendá ahora el simulacro de restore semestral — ver [restore-simulacro-semestral](../backup-restore/restore-simulacro-semestral.md), y leelo una vez ahora, con el sistema sano.

---

## Fase 7 — Observación

### Objetivo

Métricas de host, contenedores y base, logs centralizados, y las siete alertas vivas **y llegando por mail**.

### A mano

La prueba de entrega de las alertas, en la UI de Grafana — va al final.

### Comandos

```bash
echo "# 1 → Rol de monitoreo en Postgres (una sola vez)"
docker compose exec -T -u postgres postgres psql -U odoo -d postgres -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE monitoring LOGIN PASSWORD '$(cat secrets/postgres_exporter_password)';
GRANT pg_monitor TO monitoring;
SQL
```

`pg_monitor` es un rol predefinido de Postgres: da lectura de las vistas de estadísticas y nada más — es propio a propósito.

```bash
echo "# 2 → Levantar la capa de observability"
docker compose up -d prometheus loki grafana alloy
```

### Verificación

```bash
echo "# 3 → Estado de la capa de observability"
make observability-verify
```

Cubre los cuatro servicios, que ningún target de Prometheus esté caído, las tres familias de métricas que empuja Alloy, que Loki reciba logs por contenedor, los binds, y que la rotación de logs del daemon haya quedado aplicada al contenedor de Odoo.

`loki` es el único servicio sin `(healthy)` y es correcto: su imagen es distroless estricta. Su caída la cubre `up == 0` en Prometheus, que lo scrapea directo.

Grafana se abre por túnel SSH — el `3001` solo escucha en loopback. **Este es el único bloque de la guía que no se corre en el servidor**: va en la máquina desde la que vas a abrir el navegador.

```bash
echo "# 4 → Túnel para ver Grafana — DESDE TU MÁQUINA, no desde el servidor"
SRV_ADMIN='ip-de-administracion-del-servidor'
ssh -N -L 3001:127.0.0.1:3001 "<usuario>@$SRV_ADMIN"
```

Si responde `Permission denied (publickey)`, mirá a qué IP fue: un `127.0.0.1` ahí significa que el comando se está corriendo en el servidor, contra sí mismo.

Con eso, `http://localhost:3001`. Usuario `admin`, contraseña en `secrets/grafana_admin_password`. Adentro tienen que estar los **5 dashboards** y las **7 reglas de alerta**, provisionadas y de solo lectura.

**Y que las alertas lleguen.** Alertas → Contact points → `email-operador` → **Test**: tiene que llegar el mail a `ALERT_EMAIL_TO`. Si no llega, revisá en orden: saldo de créditos, remitente verificado, y `docker compose logs grafana | grep -i smtp`.

---

## Fase 8 — Puesta en producción

### Objetivo

El sistema listo para recibir datos, con todo lo que los protege ya corriendo **y ya probado una vez**. El punto de no retorno real no es el `-i base` de la fase 5 —esa base es descartable— sino el primer dato que carga un usuario.

### A mano

El cuarto y último consumidor de SMTP: que **Odoo** mande un mail propio — distinto de los tres anteriores (`curl`, la unit de systemd, Grafana). Disparar una notificación saliente —invitar un usuario alcanza— y confirmar que llega.

### Comandos

```bash
echo "# 1 → Converger el stack completo de una sola vez"
make up
```

Las fases anteriores levantaron servicio por servicio. Este `make up` es la primera vez que corre la cadena entera sin argumentos, y confirma que converge sola.

```bash
echo "# 2 → Verificación integral de las seis capas"
make verify
```

Tienen que quedar **once servicios** y **ninguno** del perfil `restore`.

### Verificación

- [ ] `make verify` sale con exit `0`
- [ ] La contraseña de `admin` ya no es `admin`
- [ ] Odoo mandó un mail propio y llegó
- [ ] Hay un snapshot de restic y un `full` de pgBackRest de la corrida de la fase 6
- [ ] Llegó el mail de prueba del contact point de Grafana
- [ ] El simulacro de restore semestral está agendado y leído una vez
- [ ] Las dos passphrases de cifrado están en el gestor de contraseñas, **fuera del servidor**

La última no es ceremonia: es lo único de esta lista que, si falta, no se puede arreglar después.

A partir de acá, la operación normal está repartida en [operacion/](../operacion/), [modulos/](../modulos/), [backup-restore/](../backup-restore/) y [credenciales/](../credenciales/).
