# Instalación

Primera puesta en marcha del repositorio: producción y staging en el servidor, desarrollo en tu máquina.

**Asume que nada existe todavía** — ni contenedores, ni base, ni backups en el bucket. Si algo ya está, este no es el documento: `make verify` dice en qué estado estás, y el resto vive en [operación](docs/operations.md) · [restore](docs/restore.md) · [troubleshooting](docs/troubleshooting.md) · [arquitectura](docs/architecture.md).

## Prerrequisitos del servidor

Lo que este documento **da por hecho**. Nada de esto es responsabilidad del repositorio, pero sin ello ninguna fase funciona.

| Requisito | Por qué | Referencia |
|---|---|---|
| Linux con `systemd` | Los backups se agendan con units y timers versionados en `config/systemd/` | — |
| Docker Engine y Compose **≥ 2.20**, habilitados al arranque | Lo exige la directiva `include:` de `compose.yaml`; sin arranque automático el stack no vuelve tras un reinicio | — |
| **Rotación de logs del daemon, configurada antes del primer contenedor** | Solo aplica a contenedores **creados después** de reiniciar el daemon. Hacerlo más tarde obliga a recrear los once | `config/docker/daemon.json` |
| Un camino de acceso administrativo que **no sea internet** | Las UIs administrativas se publican en loopback y se llegan por túnel SSH; ninguna recibe hostname público | Tailscale, WireGuard, o la VPN que uses |
| El firewall del host permitiendo `53/udp` desde la LAN | Solo si vas a usar el acceso por red local. `dnsmasq` corre en `network_mode: host`, así que es el único puerto del stack que el firewall gobierna | `ufw`, `nftables`, … |
| **El DHCP de la red repartiendo la IP del servidor como DNS** | Solo si vas a usar el acceso por red local, y **es el paso que lo hace funcionar**: `dnsmasq` resuelve el hostname para quien le pregunte, y quién le pregunta lo decide el router, no el stack | El router, o el servidor DHCP de la red |

> **El firewall del host no protege a los contenedores.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall: un `deny` no alcanza a un puerto publicado por un contenedor. El aislamiento de cada servicio es **la IP a la que se publica**, y eso ya está resuelto en los `compose.*.yaml`.

## Cómo se recorre

Es **lineal**, ordenado por dependencia técnica y no por número de spec. Cada fase termina en una **verificación** y no se avanza sin que pase; desde la 2 son `make <capa>-verify`, y el valor esperado de cada chequeo vive en `scripts/verify.sh`, no acá. Se interrumpe y se retoma: `make verify` dice dónde estabas.

Los valores propios de tu deploy salen de `.env` o de una línea de asignación al principio del bloque. **Ningún comando lleva un valor de ejemplo adentro**: si hay algo que completar, está a la vista en su propia línea.

Cada fase responde las mismas cuatro preguntas, siempre en este orden:

| Bloque | Responde |
|---|---|
| **Objetivo** | ¿Para qué existe esta fase? Qué queda andando al terminar |
| **A mano** | Lo que **no se puede automatizar**: dashboards de terceros, valores que hay que pegar, decisiones |
| **Comandos** | Todo lo que se ejecuta en la terminal, del repo o del host |
| **Verificación** | Cómo sé que terminó |

| # | Fase | Qué levanta |
|---|---|---|
| **I** | **Preparación** | |
| 1 | [Cuentas externas](#1-cuentas-externas) | |
| 2 | El repositorio | |
| **II** | **Puesta en marcha** | 11 servicios, 8 módulos |
| 3 | Borde | `dnsmasq` · `nginx` · `cloudflared` · `certbot` |
| 4 | Datos | `postgres` · `pgbouncer` |
| 5 | Addons | árbol y build |
| 6 | Aplicación | `odoo` |
| 7 | Protección | `backup` |
| 8 | Observación | `prometheus` · `loki` · `grafana` · `alloy` |
| **III** | **Cierre** | |
| 9 | Puesta en producción | |
| **IV** | **Otros entornos** | |
| 10 | Staging | servidor, bajo demanda |
| 11 | Desarrollo | tu máquina |

---

# Parte I — Preparación

## 1. Cuentas externas

**Objetivo.** Las seis cuentas creadas, las dos passphrases custodiadas, y en la mano todos los valores que carga la fase 2.

**A mano.** **Primero la zona, y ya:** creá tu dominio en Cloudflare y **delegá el DNS** apuntando los nameservers en el registrador. Puede tardar 48 h, y la verificación del dominio de envío de ZeptoMail escribe SPF/DKIM ahí, así que no arranca hasta que propague. Esas dos encadenadas son el camino crítico de toda la instalación. El resto son minutos, en cualquier orden.

| Cuenta | Qué crear | Dónde termina |
|---|---|---|
| Cloudflare — zona | Tu dominio, con el DNS **delegado** en el registrador | — |
| Cloudflare — API token | Plantilla **Edit zone DNS** sobre la zona. Con `Zone:DNS:Edit` a secas falla `403 9109` y el cert no se emite nunca | `secrets/cloudflare_api_token` |
| Cloudflare Zero Trust | Un Tunnel (Networks → Tunnels) | `secrets/cloudflare_tunnel_token` |
| Cloudflare R2 | Bucket **nuevo y vacío** —uno solo, conviven `pgbackrest/` y `restic/`— y token `Object Read & Write` acotado a él | `secrets/pgbackrest_r2_credentials` · `secrets/restic_r2_credentials` · `R2_ENDPOINT` (**sin esquema**) · `R2_BUCKET` |
| ZeptoMail | Dominio verificado, Mail Agent, y **saldo** — sin créditos la alerta se detecta pero no sale | `secrets/zeptomail_smtp_password` · `SMTP_USER` · `ALERT_EMAIL_FROM` |
| Git remoto (GitHub, GitLab…) | Token de solo lectura sobre la organización donde viven tus repos de addons. **Anotá el vencimiento** si es de los que expiran | `~/.git-credentials` del servidor (fase 5) y de tu máquina (fase 11) |

**Comandos.** Las dos passphrases de cifrado se inventan acá. Mismo comando, **dos valores distintos**: cifran repositorios separados y terminan en archivos separados. Hex y no base64: los `/ + =` rompen a cualquier consumidor que arme una URI con la credencial adentro.

```bash
echo "# 1 → Passphrase de pgBackRest, a secrets/pgbackrest_r2_credentials"
openssl rand -hex 32
```

```bash
echo "# 2 → Passphrase de restic, a secrets/restic_password (valor distinto)"
openssl rand -hex 32
```

> **Al gestor de contraseñas ahora, antes de seguir.** Perderlas deja el repositorio de backups irrecuperable — no hay procedimiento. Y no las dejes solo en el servidor: si el servidor es lo que se perdió, ahí no las vas a poder buscar. Mismo trato para el token de R2, que puede vaciar el bucket (R2 no tiene versioning). Una vez guardadas, cerrá la terminal: a diferencia de los tokens, estas dos sí quedan impresas en el scrollback.

**Verificación.** Todavía no hay repo clonado, así que los valores van en una línea de asignación. Dos de las seis cuentas se pueden probar de verdad ahora, y son las que más tarde muerden.

```bash
echo "# 3 → Completá tu zona"
ZONA='ejemplo.com'
echo "ZONA=$ZONA"
```

```bash
echo "# 4 → La zona está delegada a Cloudflare"
dig +short NS "$ZONA"
```

```bash
echo "# 5 → Token de zona DNS (pegalo y Enter, no se muestra)"
read -rs CF_TOKEN && CF_RESP=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones?name=%s"\n' "$CF_TOKEN" "$ZONA" \
  | curl -s --config -) \
  && echo "$CF_RESP" \
  && echo "$CF_RESP" | grep -q "\"name\":\"$ZONA\"" && echo "OK: token válido para $ZONA"
```

El 5 imprime el JSON crudo y, si matchea tu zona, un `OK` final. Sin `OK`: `1000` en el JSON = token mal copiado · `9109` = le falta `Zone:Read` · `"result":[]` = el token apunta a otra zona.

Y que ZeptoMail manda de verdad — credencial, remitente verificado y saldo, en un solo tiro:

```bash
echo "# 6 → Completá estos tres antes de seguir"
ZM_USER='emailapikey'; ZM_FROM='remitente-verificado@tu-dominio'; ZM_TO='donde-querés-recibir@ejemplo'
echo "ZM_USER=$ZM_USER · ZM_FROM=$ZM_FROM · ZM_TO=$ZM_TO"
```

```bash
echo "# 7 → Token del Mail Agent (pegalo y Enter, no se muestra)"
read -rs ZM_TOKEN && printf 'From: %s\nTo: %s\nSubject: prueba\n\nok\n' "$ZM_FROM" "$ZM_TO" \
  | curl -sS --ssl-reqd --url smtp://smtp.zeptomail.com:587 \
      --user "$ZM_USER:$ZM_TOKEN" --mail-from "$ZM_FROM" --mail-rcpt "$ZM_TO" --upload-file - \
  && echo "OK: aceptado por ZeptoMail — confirmá que llegó a $ZM_TO"
```

`ZM_USER` **no es tu dirección de correo**: sale de ZeptoMail → Mail Agents → el agente → SMTP & API, donde figura el `Username` literal (suele ser `emailapikey`). Y el token va **sin el prefijo `Zoho-enczapikey`**, que es para el header HTTP de la API, no para SMTP. Las dos cosas dan `curl: (67) Login denied`.

Ese usuario es el que después va a `SMTP_USER` en `.env` y el que usa `scripts/failure-notify.sh` en la fase 7: acertarlo acá evita que el aviso de backup fallido falle en silencio más adelante.

En los dos bloques con token, el `read` va **en el último comando** y lo que usa el valor cuelga del mismo `&&`: si quedara una línea suelta debajo, `read` se la comería como valor y el `curl` no correría — sin error y sin salida.

Lo que no se puede probar todavía: el token del Tunnel (fase 3), R2 (fase 4) y el del git remoto (fase 5).

---

## 2. El repositorio

**Objetivo.** El repo clonado en el último release, con `.env` y los 11 secrets cargados y validados. Nada levantado todavía.

**A mano.** `secrets-init` deja **11 archivos**: 5 **generados** que no se tocan nunca —`postgres_password`, `pgbouncer_credentials`, `odoo_admin_password`, `grafana_admin_password`, `postgres_exporter_password`— y 6 con el marcador `CAMBIAR`, que se llenan con lo que juntaste en la fase 1 (columna *Dónde termina*). Tres detalles de formato:

- `cloudflare_api_token`: sin comillas y **sin salto de línea final** — `nano -L`. Cloudflare emite dos formatos según cuándo lo creaste: 40 caracteres el viejo, `cfut_...` (~46) el nuevo — los dos son válidos, no importa cuál te tocó.
- `pgbackrest_r2_credentials` y `restic_r2_credentials` ya vienen con su esqueleto INI. **La misma clave de R2 va en los dos**, en sintaxis distinta: al rotarla hay que tocar ambos.
- Editor interactivo, nunca `echo >>`: así el token no queda en el historial.

En `.env`, seis claves que la fase 1 no cubre. Las otras cuatro (`R2_ENDPOINT`, `R2_BUCKET`, `SMTP_USER`, `ALERT_EMAIL_FROM`) salen de su tabla.

Las dos primeras definen **qué stack es este checkout**, y son las mismas dos en los tres entornos. Ningún archivo de Compose declara el nombre: si falta, el proyecto pasa a llamarse como el directorio, y con él sus volúmenes y sus imágenes.

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | Nombre del stack: `production` acá. Gobierna contenedores, volúmenes, redes y tags de imagen |
| `COMPOSE_FILE` | Qué capas se levantan: `compose.yaml` para producción |
| `PUBLIC_HOSTNAME` | El hostname público de esta instancia, el mismo que va a servir el Tunnel |
| `LOCAL_IP` | La IP LAN del servidor — **real y de una interfaz existente**: `dnsmasq` bindea exactamente ahí y si no, queda `unhealthy` |
| `PGBACKREST_STANZA` | Nombre de la stanza, estable — cambiarlo deja huérfanos los backups viejos |
| `ALERT_EMAIL_TO` | Destinatario de los avisos de backup y de las alertas de Grafana |

**Comandos.**

```bash
echo "# 1 → Completá la URL de tu fork"
REPO_URL='git@github.com:tu-organizacion/infrastructure-odoo.git'
echo "REPO_URL=$REPO_URL"
```

```bash
echo "# 2 → Clonar y fijar al último release"
git clone "$REPO_URL" && cd "$(basename "$REPO_URL" .git)"
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

```bash
echo "# 3 → Esqueleto de config y secrets"
cp .env.prod.example .env
make secrets-init
```

Al **último tag**, no al `HEAD` de la rama por defecto: es el mismo criterio de "nunca `:latest`" aplicado al propio checkout, con `HEAD` detached como guard-rail contra corregir código en el servidor. `secrets-init` imprime cuáles quedaron con `CAMBIAR`, y es idempotente: nunca pisa un valor ya cargado.

```bash
echo "# 4 → IPs del servidor — anotá las dos primeras, las piden las fases 3 y 6"
echo "LAN:     $(hostname -I | awk '{print $1}')"
echo "Pública: $(curl -s ifconfig.me)"
```

`LAN` es la que va a `LOCAL_IP` y tiene que caer en tu subred local: si sale una IP de tu VPN o de un bridge de Docker, agarró la interfaz equivocada. Anotá además la IP por la que administrás el servidor — la de tu VPN —, que la usan los túneles SSH de las fases 3 y 8.

Ahora cargá los valores de arriba. Después:

```bash
echo "# 5 → Permisos y grupo de cada secret"
sudo make secrets-perms
```

Deja cada archivo en `640` con el grupo del proceso **no-root** que lo lee. Necesita root porque `chgrp` a un GID ajeno lo exige.

```bash
echo "# 6 → Cargar .env en la shell — repetilo en cada sesión nueva"
set -a; . ./.env; set +a
echo "OK: PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME · LOCAL_IP=$LOCAL_IP"
```

De acá en adelante los comandos usan esas variables en vez de valores literales. Si abrís una terminal nueva, volvé a correr este bloque.

**Verificación.**

```bash
echo "# 7 → Prerrequisitos del servidor y config del repo"
make host-verify
```

Cubre versión de Compose, arranque automático de Docker, `.env` sin claves vacías, la identidad declarada del stack, permisos y GID de los 11 secrets, y la superficie publicada del host. Es también lo que valida los prerrequisitos que este documento da por hechos.

---

# Parte II — Puesta en marcha

## 3. Borde

**Objetivo.** El certificado emitido, nginx sirviendo con él, el Tunnel conectado y `dnsmasq` resolviendo el hostname a la IP local para la LAN.

**El orden importa y es al revés de lo intuitivo: primero el certificado, después el proxy.** nginx no arranca si el archivo del certificado no existe, y con DNS-01 certbot no necesita que nginx esté vivo para emitirlo — valida contra la API de Cloudflare, no contra el puerto 80.

**A mano.** El **Public Hostname del Tunnel**, en Zero Trust → Networks → Tunnels → el Tunnel → Public Hostname. Va a mano porque el Tunnel es *remotely-managed*: no hay archivo de este repo que lo reemplace.

| Campo | Valor |
|---|---|
| Subdomain + Domain | Los que componen tu `PUBLIC_HOSTNAME` |
| Service | `https://nginx:443` — comparten la red `edge`, se resuelven por nombre |
| TLS → **Origin Server Name** | Tu `PUBLIC_HOSTNAME` completo — **el que se olvida** |
| TLS → No TLS Verify | desactivado |

**El campo Origin Server Name vacío no se ve vacío.** El dashboard le pone de placeholder la palabra `Null` en gris, que a simple vista se confunde con un valor ya cargado — sobre todo si volviste a este panel solo para tocar el campo Service después de corregir otra cosa, y no repasaste la tabla entera. Si no lo ves escrito en texto negro, no está seteado.

Sin **Origin Server Name**, `cloudflared` cae al hostname del propio Service (`nginx`) para validar el certificado, que no es a quién se lo emitió Let's Encrypt, y el sitio entero da **502**. No se manifiesta acá: recién en la fase 6, con Odoo sirviendo tráfico real — y ningún `make <capa>-verify` lo detecta antes, porque es config de Cloudflare, no de este repositorio. El error, en `docker compose logs cloudflared`, es inconfundible:

```
tls: failed to verify certificate: x509: certificate is valid for <tu PUBLIC_HOSTNAME>, not nginx
```

**Comandos.**

```bash
echo "# 1 → Emitir el certificado (one-off; nginx todavía no existe)"
make cert-issue
```

```bash
echo "# 2 → Levantar el borde (dnsmasq se construye la primera vez)"
docker compose up -d cloudflared nginx dnsmasq
```

**El hostname público va a dar 502 al terminar esta fase, y está bien.** nginx ya sirve con el certificado real, pero su upstream —Odoo— no existe hasta la fase 6. Es el estado correcto, no un fallo.

**Verificación.**

```bash
echo "# 3 → Estado del borde"
make edge-verify
```

Cubre los tres servicios `healthy`, que la config renderizada no tenga variables sin sustituir, que el `server_name` sea tu hostname, que el `proxy_pass` vaya por variable con el resolver de Docker declarado, los días que le quedan al certificado, las conexiones registradas del Tunnel, el log de nginx sin errores, los binds (`80`/`443` en `${LOCAL_IP}`) y el token de Cloudflare contra la API.

Si `dnsmasq` queda `unhealthy`, las dos causas típicas en un servidor nuevo son el `53` ya ocupado por el resolver del sistema, o el `53/udp` bloqueado en el firewall del host (ver Prerrequisitos) — está en [troubleshooting](docs/troubleshooting.md).

Dos chequeos **no se pueden correr en el servidor**: cada bloque va en la máquina que dice, y ahí no tenés `.env`, así que los valores vuelven a la línea de asignación.

```bash
echo "# 4 → Desde otro equipo de la LAN: las dos líneas tienen que dar la IP local del servidor"
HOST_PUB='el-hostname-publico'; SRV_LAN='ip-lan-del-servidor'
echo "4a — dnsmasq responde:"; dig +short "$HOST_PUB" @"$SRV_LAN"
echo "4b — la LAN le pregunta:"; dig +short "$HOST_PUB"
```

**El que importa es el 4b.** El `@` del 4a le pregunta a `dnsmasq` directamente, así que prueba que responde bien — no que ningún equipo lo esté usando. Quién resuelve para la LAN lo decide el DHCP del router (ver Prerrequisitos), no este repositorio. Si el 4a da la IP local y el 4b devuelve una IP de Cloudflare, `dnsmasq` está sano y **no lo usa nadie**: la LAN sale a internet para llegar a un servidor que tiene al lado, y se queda sin acceso si internet se cae.

```bash
echo "# 5 → Desde fuera de la LAN (datos móviles): tiene que fallar"
SRV_PUB='ip-publica-del-servidor'
nc -z -w2 "$SRV_PUB" 443 && echo "MAL: el router está reenviando el 443" || echo "OK: sin reenvío"
```

El `dig` **desde el propio servidor no sirve**: puede dar timeout por NAT sin que haya nada roto. Y devuelve la IP local, no una de Cloudflare — ese split-horizon es la razón por la que el chequeo público de la fase 6 exige headers de Cloudflare y no solo un `200`.

nginx no publica ninguna UI: no hay dashboard que abrir. Su estado se lee del log, que sale en JSON a `docker compose logs nginx`, y de `make edge-verify`.

---

## 4. Datos

**Objetivo.** La base corriendo y **ya respaldándose**, antes de que exista un solo dato adentro.

**A mano.** Ninguno. La única decisión de esta fase es de orden, no de configuración — y va explicada abajo.

**Comandos.**

```bash
echo "# 1 → Levantar la base y el pooler (postgres se construye la primera vez)"
docker compose up -d postgres pgbouncer
```

La imagen propia es `postgres:17.10` más `pgbackrest`: el `archive_command` lo ejecuta el proceso de la base, así que el binario tiene que vivir ahí adentro. El rol `odoo` y su password son **definitivos** — la fase 6 reusa esa misma credencial sin rotarla, y solo crea la base sobre ese rol.

```bash
echo "# 2 → Crear la stanza y probar el archivado hasta R2"
docker compose exec -T -u postgres postgres pgbackrest stanza-create
docker compose exec -T -u postgres postgres pgbackrest check && echo "OK: el archive_command llega a R2"
```

**Va acá y no en la fase 7, y la ventana tiene que ser cero.** Postgres arranca con `archive_mode = on` y el `archive_command` apuntando a R2, así que **cada archivado falla hasta que la stanza exista** y los WAL se acumulan en `pg_wal`. Crear la stanza en la fase de protección dejaría un hueco de varias fases con el disco llenándose.

`check` fuerza un switch de WAL y lo sigue hasta R2. Es la única prueba de que el `archive_command` funciona de verdad y no solo de que la config parsea — y es también **donde se prueba por primera vez la credencial de R2**, que la fase 1 no podía verificar. Si falla acá, mirá el endpoint (va sin esquema), el bucket y la clave.

**Verificación.**

```bash
echo "# 3 → Estado de la capa de datos"
make db-verify
```

Cubre los dos servicios `healthy`, `archive_mode` y `archive_command`, la stanza cifrada en R2, que no haya WAL pendiente de archivar, los logs sin errores de permisos, que ninguno de los dos puertos esté publicado, y la **autenticación real a través de PgBouncer**.

Ese último es el que importa: `pg_isready` solo pregunta si el puerto responde, así que un `auth_file` ilegible o mal apuntado lo pasa igual, y el fallo aparecería recién en la fase 6 como un error de credenciales de Odoo que no menciona a PgBouncer.

```bash
echo "# 4 → Desde otro equipo de la LAN: ninguno de los dos puertos existe hacia afuera"
SRV_LAN='ip-lan-del-servidor'
for p in 5432 6432; do nc -z -w2 "$SRV_LAN" "$p" && echo "MAL: $p alcanzable" || echo "OK: $p inalcanzable"; done
```

Los dos viven solo en la red `app`; desde afuera no hay más camino que Odoo.

---

## 5. Addons

**Objetivo.** El árbol de módulos en disco y la imagen de Odoo construida. **La fase 6 no arranca sin esto**: el entrypoint aborta a propósito si el `addons_path` queda vacío — los addons llegan por bind-mount, así que su presencia ya no la garantiza la imagen.

**A mano.** Primero, `addons/addons.txt` **no existe todavía** — es local a este checkout, igual que `.env`, y por la misma razón: a diferencia de `odoo.conf`, tu manifiesto real difiere de verdad entre producción, staging y development, así que no viaja versionado. Se bootstrapea desde su plantilla (bloque 1 de Comandos) y se completa con tus repos, uno por línea (`URL categoría`) — al menos el que provee `bus_alt_connection` (obligatorio, ver comentario del propio archivo) aunque no tengas módulos propios; si no tenés ninguno todavía, forkealo primero a tu organización.

Sin al menos una línea el entrypoint de Odoo aborta al arrancar (fase 6), y `scripts/addons.sh sync` corta con error en vez de mentir con un árbol vacío — nombrando el mismo `cp` de acá si el archivo falta.

Segundo, el token de la fase 1, que se pega en el bloque 3. Lo piden los repos privados del manifiesto; los forks públicos no.

No es un secret de Compose y es la **única excepción escrita** al principio de secretos: el clonado ocurre en el host y ningún contenedor lo consume. Es de solo lectura porque el servidor nunca escribe en un repo de addons — todos los merges pasan por tu máquina.

**Comandos.**

```bash
echo "# 1 → Bootstrapear el manifiesto desde su plantilla"
cp addons/addons.txt.example addons/addons.txt
${EDITOR:-vi} addons/addons.txt
```

```bash
echo "# 2 → Completá tu usuario y el host HTTPS de los repos de addons — no un alias SSH propio"
GIT_USER='tu-usuario'; GIT_HOST='github.com'
echo "GIT_USER=$GIT_USER · GIT_HOST=$GIT_HOST"
```

```bash
echo "# 3 → Token en el credential store del host (pegalo y Enter, no se muestra)"
git config --global credential.helper store
read -rs GIT_TOKEN && printf 'https://%s:%s@%s\n' "$GIT_USER" "$GIT_TOKEN" "$GIT_HOST" >> ~/.git-credentials \
  && chmod 600 ~/.git-credentials && echo "OK: credencial guardada"
```

```bash
echo "# 4 → Clonar los repos del manifiesto y armar el árbol"
make addons-sync
```

Lee `addons/addons.txt` —tu manifiesto, local a este checkout, URL más categoría— y deja un clon bare por módulo bajo `addons/.repos/` más un `git worktree` en `addons/<categoría>/<repo>`. La rama la decide `ADDONS_BRANCH` en `.env`, cuyo default es la versión del tag `FROM odoo:` del Dockerfile: en producción no hay nada que declarar. El resto de `addons/` va gitignoreado —el manifiesto real, lo clonado adentro de cada categoría, y `.repos/`— y solo la plantilla (`addons.txt.example`) y el esqueleto vacío de las cuatro categorías se versionan. Sumar un módulo más adelante es una línea en tu `addons.txt` y volver a correr esto.

```bash
echo "# 5 → Construir la imagen de Odoo"
docker compose build odoo && echo "OK: imagen construida"
```

**El build no clona nada.** Instala las dependencias Python de `docker/odoo/requirements.txt` y copia el entrypoint, nada más. Existe solo porque los addons declaran `external_dependencies` y sin imagen propia no habría dónde instalarlas — por eso vive en esta fase y no en la 6. La consecuencia buscada: **desplegar un cambio de módulo no vuelve a requerir un rebuild**, son `make addons-sync` y un `-u`.

**Verificación.**

```bash
echo "# 6 → Estado de cada worktree"
make addons
```

Encabeza con la rama declarada y sigue con una fila por repo del manifiesto, todas en `limpio`. Un `(sin worktree)` o un `sucio` es un sync incompleto. Si un repo privado falló con `Repository not found` o `Authentication failed`, el token no tiene los permisos justos: alcanza con lectura de contenidos sobre tu organización, y si es de los que expiran, revisá también que no haya vencido.

Es un chequeo visual, no un exit code: `make odoo-verify` lo vuelve a validar mecánicamente en la fase siguiente, junto con el resto de la aplicación.

Este árbol es el de **este** checkout. Los otros entornos son checkouts propios, con su `.env` y su `ADDONS_BRANCH`; los arman las fases 10 y 11.

---

## 6. Aplicación

**Objetivo.** Odoo sirviendo por el hostname público con certificado propio de Let's Encrypt. Acá se cierra el 502 que dejó la fase 3 y se prueba la cadena Cloudflare → Tunnel → nginx → Odoo entera.

**A mano.** **La contraseña de `admin`, apenas el sitio responda y antes que cualquier otra cosa.** El `-i base` del primer arranque la deja en `admin`, y para ese momento el sitio ya está publicado en internet por el Tunnel.

Entrá a `https://$PUBLIC_HOSTNAME` → Ajustes → Usuarios → `admin` → cambiar contraseña. Es distinta del **master password** (`admin_passwd`), que se gestiona vía `secrets:` y no se toca acá.

**Comandos.**

```bash
echo "# 1 → Levantar Odoo (el primer arranque tarda)"
docker compose up -d odoo
docker compose logs -f odoo
```

El entrypoint detecta que la base está vacía y corre `-i base --stop-after-init` **conectándose directo a `postgres:5432`, no a PgBouncer**: el modo transacción no soporta los advisory locks ni el DDL que necesita una inicialización. Recién después arranca el servidor apuntando al pooler. Por eso el healthcheck tiene `start_period: 90s`. Esperá `HTTP service (werkzeug) running` y cortá el `logs -f`.

**Ahora cambiá la contraseña de `admin`** (bloque de arriba). Después, si corresponde instalar módulos:

```bash
echo "# 2 → Instalar módulos en la base (opcional, un paso explícito)"
make odoo-install MODULES=nombre_del_modulo
```

Detiene el servicio, corre el `-i` en un contenedor efímero y lo vuelve a levantar. Es deliberado que sea explícito y no automático: un `-u` de varios minutos disparado en cada arranque se repetiría en el restart de un crash, alargando la caída en vez de resolverla. El ciclo completo está en [addons](docs/addons.md).

`bus_alt_connection` no entra en esa lista: se carga por `server_wide_modules` en `odoo.conf`, no por instalación en la base.

**Verificación.**

```bash
echo "# 3 → Estado de la aplicación"
make odoo-verify
```

Cubre el servicio `healthy`, los logs sin errores de permisos, Odoo respondiendo en su `:8069`, los worktrees limpios, las tres rutas en la config renderizada de nginx, el gestor de bases deshabilitado, los puertos sin publicar, y el **certificado**: emisor Let's Encrypt y con más de 21 días de vigencia.

Tres cosas quedan a mano.

```bash
echo "# 4 → ¿Por dónde va a salir el pedido? Esto decide si el chequeo 5 vale"
dig +short "$PUBLIC_HOSTNAME"
```

Si devuelve IPs de Cloudflare, el 5 es válido desde el propio servidor. Si devuelve `$LOCAL_IP`, el host está usando `dnsmasq` como resolver: el pedido iría directo a nginx sin pasar por Cloudflare y daría `200` **aunque el Tunnel esté roto**. En ese caso corré el 5 desde otra red.

```bash
echo "# 5 → La cadena pública completa: tienen que salir LOS TRES headers"
curl -sI "https://$PUBLIC_HOSTNAME/web/login" | grep -iE "^HTTP|^server:|^cf-ray:"
```

Solo Cloudflare agrega `server:` y `cf-ray:`. Un `200` sin ellos significa que el pedido nunca salió a internet. Si en cambio da **502**, confirmá el Origin Server Name de la fase 3 con:

```bash
docker compose logs cloudflared | grep "certificate is valid for"
```

`certificate is valid for <tu hostname>, not nginx` confirma la causa: el campo quedó vacío (o se vació sin querer) en Zero Trust.

```bash
echo "# 6 → Rate-limit del login: diez 400 y después 503"
for i in $(seq 1 20); do curl -sk -o /dev/null -w "%{http_code} " -X POST \
  --resolve "$PUBLIC_HOSTNAME:443:$LOCAL_IP" "https://$PUBLIC_HOSTNAME/web/login"; done; echo
```

El `400` es Odoo rechazando un POST sin token CSRF — respuesta válida, no un fallo; lo que se mide es el corte en el 11.º (`average=2`, `burst=10`), que `limit_req` devuelve como **503**, no como 429. Va directo a nginx por `--resolve` a propósito, y a `$LOCAL_IP` porque es ahí donde publica: con la latencia de Cloudflare de por medio (~300 ms por request) el bucket repone fichas más rápido de lo que el loop las consume y el corte no aparece nunca, aunque la zona esté perfecta. Por eso tampoco está en `verify.sh`: dispara un rate-limiter deliberadamente y no corresponde en cada corrida.

**Y el chatter, con dos sesiones abiertas:** mandá un mensaje y confirmá que aparece solo, sin recargar. Prueba dos cosas de un tiro — que nginx rutea `/websocket` al worker gevent (`8072`) con la ruta entera, y que `bus_alt_connection` está activo: sin él, el modo transacción de PgBouncer rompe el `LISTEN/NOTIFY` del que depende el bus y el mensaje no llegaría hasta recargar.

---

## 7. Protección

**Objetivo.** Las dos mitades del backup corriendo, probadas una vez de punta a punta, y avisando por mail si fallan. pgBackRest no aporta contenedor: vive dentro del de Postgres, y su stanza quedó operativa en la fase 4.

**A mano.** Ninguno. Como en la 4, lo único propio de esta fase es el orden: va **después** de la 6 porque su verificación exige un snapshot, y un snapshot exige que exista un filestore.

**Comandos.**

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

El `sudo -v` adelante no es decorativo: si `sudo` pidiera contraseña en medio del pegado, se comería la línea siguiente como respuesta y ese comando **no correría**. El glob incluye `odoo-notify@.service`, la unit plantilla que instancia el `OnFailure=` de las otras dos: sin ella, un backup que falle **no avisa** y nada más lo delata.

```bash
echo "# 3 → Primera corrida completa (tarda; ver abajo antes de arrancarla)"
make backup
```

Encadena `pgbackrest check` → `backup --type=diff` → registro de addons → `restic backup` → `forget --prune`. **El orden no es casual:** pgBackRest primero y restic después, siempre. Un snapshot de filestore más nuevo que el backup de base deja archivos huérfanos, que son inofensivos; uno más viejo deja filas de `ir_attachment` apuntando a archivos que no existen, que es destructivo y silencioso.

**Va a parecer trabada y no lo está.** Después de `backup start archive = …` pgBackRest no imprime nada hasta terminar: sube el cluster archivo por archivo, un objeto a R2 por cada uno. En una instalación nueva son ~2000 archivos y **más de 10 minutos**, aunque el total comprimido sea de pocos MB — manda la latencia por objeto, no el tamaño. `restic backup` después es igual de callado. **No le des Ctrl-C**: un full abortado deja basura parcial en el repositorio. Para ver que avanza, desde otra sesión:

```bash
docker compose exec -T postgres tail -f /var/log/pgbackrest/*-backup.log
```

El primero sale `full` y no `diff`: pgBackRest promueve solo cuando no hay un full previo del cual diferir. La corrida deja además `state/meta/addons.txt` dentro del snapshot — repo, rama y commit de cada worktree de producción. Sin pineo por commit, es lo único que le dice a un restore a qué código corresponden esos datos.

**Verificación.**

```bash
echo "# 4 → Estado de la capa de protección"
make backups-verify
```

Cubre el snapshot de restic, el full de pgBackRest, el registro de addons, los dos timers activos, el `OnFailure=` cableado con su unit plantilla instalada, y que ningún contenedor del perfil `restore` esté corriendo.

Si el contenedor sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora. **No lo recrees para forzarlo** — le cambiarías el hostname, y con eso el grupo `(host, paths)` por el que restic agrupa la retención.

```bash
echo "# 5 → El aviso de fallo, de punta a punta"
sudo systemctl start odoo-notify@prueba.service
systemctl is-active odoo-notify@prueba.service; systemctl show -p Result --value odoo-notify@prueba.service
```

Dispara la unit real, no el script suelto: prueba el cableado, la ruta absoluta del `ExecStart` y el envío. Tiene que dar `Result=success` **y llegar el mail**. Un rechazo del SMTP acá es saldo o remitente sin verificar — lo mismo que ya probaste en la fase 1, ahora desde el servidor y con la credencial que quedó en `secrets/`.

> **Un backup sin probar no es un backup**, y los principios lo exigen. Agendá ahora el simulacro de restore semestral: el procedimiento está en [restore](docs/restore.md) § Escenario C, y ese documento cubre además los dos escenarios reales. **Leelo una vez ahora, con el sistema sano** — no la primera vez a las 3 de la mañana.

---

## 8. Observación

**Objetivo.** Métricas de host, contenedores y base, logs centralizados, y las siete alertas vivas **y llegando por mail**. Alloy es el único agente: embebe los colectores de `node_exporter`, `cAdvisor` y el exporter de Postgres como componentes nativos —mismos colectores, mismos nombres de métrica— y además envía los logs.

**A mano.** La prueba de entrega de las alertas, en la UI de Grafana. Es lo único de esta fase que ningún script puede hacer, y va al final.

**Comandos.**

```bash
echo "# 1 → Rol de monitoreo en Postgres (una sola vez)"
docker compose exec -T -u postgres postgres psql -U odoo -d postgres -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE monitoring LOGIN PASSWORD '$(cat secrets/postgres_exporter_password)';
GRANT pg_monitor TO monitoring;
SQL
```

`pg_monitor` es un rol predefinido de Postgres: da lectura de las vistas de estadísticas y nada más. Es propio a propósito — el contenedor que tiene el socket de Docker y el stream de logs de todo el stack no debe portar la credencial de la aplicación. Si algún día rotás ese secret, hace falta además un `ALTER ROLE monitoring PASSWORD`: el archivo por sí solo no cambia la base.

```bash
echo "# 2 → Levantar la capa de observability"
docker compose up -d prometheus loki grafana alloy
```

**Verificación.**

```bash
echo "# 3 → Estado de la capa de observability"
make observability-verify
```

Cubre los cuatro servicios, que ningún target de Prometheus esté caído, las tres familias de métricas que empuja Alloy (host, contenedores y base), que Loki reciba logs por contenedor, los binds, y —cerrando el prerrequisito del principio— que la **rotación de logs del daemon** haya quedado efectivamente aplicada al contenedor de Odoo.

`loki` es el único servicio sin `(healthy)` y es correcto: su imagen es distroless estricta, no hay binario con el cual ejecutar un healthcheck. Su caída la cubre `up == 0` en Prometheus, que lo scrapea directo.

Eso último no es un detalle de implementación sino la razón de que la topología sea híbrida: si todo se empujara por el agente, la muerte de Alloy **no dispararía ninguna alerta** — las series simplemente dejarían de llegar, y un umbral sobre una serie ausente no alerta nada. Por eso Prometheus scrapea por pull todo lo que ya expone HTTP (`cloudflared`, Loki, Grafana, sí mismo **y el propio Alloy**), y el agente solo empuja lo que ningún pull alcanza.

Grafana se abre por túnel SSH — el `3001` solo escucha en loopback. **Este es el único bloque de la guía que no se corre en el servidor**: va en la máquina desde la que vas a abrir el navegador, y `SRV_ADMIN` tiene que resolver al servidor **desde ahí**. Ojo con el hostname del servidor: en el servidor mismo resuelve a loopback, y `dnsmasq` no lo sirve — solo sirve `PUBLIC_HOSTNAME`.

```bash
echo "# 4 → Túnel para ver Grafana — DESDE TU MÁQUINA, no desde el servidor"
SRV_ADMIN='ip-de-administracion-del-servidor'
ssh -N -L 3001:127.0.0.1:3001 "<usuario>@$SRV_ADMIN"
```

Si responde `Permission denied (publickey)`, mirá a qué IP fue: `ssh -v … | grep 'Connecting to'`. Un `127.0.0.1` o `127.0.1.1` ahí significa que el comando se está corriendo en el servidor, contra sí mismo.

Con eso, `http://localhost:3001`. Usuario `admin`, contraseña en `secrets/grafana_admin_password`. Adentro tienen que estar los **5 dashboards** y las **7 reglas de alerta**, todas provisionadas y de solo lectura: se definen como archivos en `config/grafana/provisioning/`, no como estado clickeado que se perdería al recrear el contenedor.

**Y que las alertas lleguen.** Todo lo anterior verifica que **disparan**; falta que **salgan**. Alertas → Contact points → `email-operador` → **Test**: tiene que llegar el mail a `ALERT_EMAIL_TO`. Si no llega, revisá en ese orden: saldo de créditos, remitente verificado, y `docker compose logs grafana | grep -i smtp`.

Es la tercera vez que se prueba el mismo camino SMTP —en la fase 1 con la credencial en la mano, en la 7 desde la unit de systemd, y acá desde Grafana— y las tres valen: son tres consumidores distintos de la misma cuenta, y cada uno falla por su lado.

---

# Parte III — Cierre

## 9. Puesta en producción

**Objetivo.** El sistema listo para recibir datos, con todo lo que los protege ya corriendo **y ya probado una vez**.

Porque el punto de no retorno real no es el `-i base` de la fase 6 —esa base es descartable— sino **el primer dato que carga un usuario**, y eso pasa después de este documento. Terminar la instalación significa llegar a ese momento sin nada pendiente.

**A mano.** El cuarto y último consumidor de SMTP: **que Odoo mande un mail propio**. Es distinto de los tres anteriores, que probaron `curl`, la unit de systemd y Grafana; este prueba la configuración de `odoo.conf` con el `smtp_user` y la contraseña que le inyecta el entrypoint. Disparar una notificación saliente —invitar un usuario alcanza— y confirmar que llega.

**Comandos.**

```bash
echo "# 1 → Converger el stack completo de una sola vez"
make up
```

Las fases levantaron servicio por servicio con `docker compose up -d <servicios>`. Este `make up` es la primera vez que se ejecuta la cadena entera de `include:` sin argumentos, y confirma que **converge sola**: si alguna fase hubiera dejado algo a medias, acá aparece. De acá en adelante es el comando de operación normal.

```bash
echo "# 2 → Verificación integral de las seis capas"
make verify
```

Tienen que quedar **once servicios** y **ninguno** del perfil `restore`.

**Verificación.** Terminado cuando las siete líneas pasan:

- [ ] `make verify` sale con exit `0`
- [ ] La contraseña de `admin` ya no es `admin`
- [ ] Odoo mandó un mail propio y llegó
- [ ] Hay un snapshot de restic y un `full` de pgBackRest de la corrida de la fase 7
- [ ] Llegó el mail de prueba del contact point de Grafana
- [ ] El simulacro de restore semestral está agendado y [restore](docs/restore.md) leído una vez
- [ ] Las dos passphrases de cifrado están en el gestor de contraseñas, **fuera del servidor**

La última no es ceremonia: es lo único de esta lista que, si falta, no se puede arreglar después.

A partir de acá el documento es [operación](docs/operations.md).

---

# Parte IV — Otros entornos

> Los dos entrypoints existen: `compose.staging.yaml` y `compose.dev.yaml`. Cuál se usa lo dice `COMPOSE_FILE` en `.env` — es el único lugar donde se elige el stack. Los árboles de addons de los tres entornos los crea `scripts/addons.sh`. Qué comparte cada stack está en [docs/stacks.md](docs/stacks.md).

## 10. Staging

**Objetivo.** Un segundo stack en el mismo servidor, con su hostname, su certificado y su túnel, **sembrado con los datos de producción por un restore**. Sembrarlo y hacer el simulacro de restore son la misma operación: el paso que los principios exigen y que siempre se posterga acá tiene ocasión natural.

Lleva proxy, borde, datos, aplicación y restore. **No lleva backups, observabilidad ni `dnsmasq`**: los tres son exclusivos de producción, y el `53` en `network_mode: host` no admite un segundo de ninguna forma.

**A mano.** Un **Tunnel propio** en Zero Trust, no el de producción: el token es el que distingue a los dos stacks. Mismos campos que la fase 3, con el hostname de staging en Subdomain y en **Origin Server Name**, y `https://nginx:443` como Service.

Los 8 secrets se reparten en tres grupos, y solo el último es trabajo nuevo:

| Grupo | Cuáles | De dónde salen |
|---|---|---|
| Generados | `postgres_password` · `pgbouncer_credentials` · `odoo_admin_password` | `secrets-init` los saca de `openssl`; no se tocan |
| Copiados de producción | `restic_password` · `pgbackrest_r2_credentials` · `restic_r2_credentials` | Abren **su** repositorio: sin los mismos valores no hay nada que restaurar |
| De Cloudflare | `cloudflare_api_token` · `cloudflare_tunnel_token` | El API token puede ser el mismo de producción — es la misma zona. El del Tunnel es el del Tunnel nuevo |

En `.env`, ocho claves. Las de R2 y la stanza son **las de producción**, porque de ahí lee:

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | `staging` |
| `COMPOSE_FILE` | `compose.staging.yaml` |
| `PG_ARCHIVE_MODE` | `off` — **la que no se puede olvidar**, ver abajo |
| `PUBLIC_HOSTNAME` | El hostname de staging, distinto del de producción |
| `PGBACKREST_STANZA` · `R2_ENDPOINT` · `R2_BUCKET` | Los mismos valores que producción: es su repositorio el que se restaura |
| `ADDONS_BRANCH` | `<versión>-stag`, la rama de staging de los repos de addons |

Lo que las capas ausentes necesitarían —SMTP, alertas, retenciones— **no está en la plantilla**, y `LOCAL_IP` tampoco: staging no publica puertos, entra solo por el túnel. Si copiás una clave de más desde el `.env` de producción, dejala con valor o borrala: `make host-verify` marca las vacías.

> **`PG_ARCHIVE_MODE=off` es la línea que protege los backups de producción.** Staging apunta a la stanza de producción para poder restaurar; con el archivado prendido su propio Postgres le empuja WAL a ese repositorio y lo contamina desde el entorno que existe para romper cosas. Lo verifica `make db-verify`, que en un stack sin capa de backups **exige** que esté apagado.

**Comandos.**

```bash
echo "# 1 → Clonar en su propio directorio, fijado al último tag"
git clone "$REPO_URL" /srv/odoo-staging && cd /srv/odoo-staging
git fetch --tags && git checkout "$(git describe --tags --abbrev=0)"
```

Checkout propio, como producción: `.env`, `secrets/`, `state/` y el árbol de addons son de este directorio y de ningún otro. Es lo que hace que un error en staging no pueda alcanzar las credenciales del entorno real.

```bash
echo "# 2 → Config primero: el .env es lo que dice qué stack es este"
cp .env.stag.example .env
${EDITOR:-vi} .env    # las claves de la tabla de arriba; COMPOSE_FILE ya viene puesto
```

**El `.env` se completa antes de `secrets-init`, no después.** El script le pregunta a la composición cuáles secrets lleva este stack, y quién es la composición lo dice `COMPOSE_FILE`. La plantilla ya trae el de staging, así que el orden alcanza con respetarlo: `secrets-init` nunca pisa un archivo que ya existe, y un secret creado de más queda inerte y con `CAMBIAR` para siempre.

```bash
echo "# 3 → Los 8 secrets que declara este entrypoint"
make secrets-init
```

`secrets-init` crea 8 y omite los 3 de producción. Cargá ahora los valores de la tabla de secrets, y después:

```bash
echo "# 4 → Permisos y grupo, y cargar .env en la shell"
sudo make secrets-perms
set -a; . ./.env; set +a
```

```bash
echo "# 5 → Certificado propio y árbol de addons de la rama -stag"
make cert-issue
make addons-sync
docker compose build
```

```bash
echo "# 6 → Sembrar la base desde el repositorio de producción"
make restore-up
docker compose exec restore-db pgbackrest restore --archive-mode=off
make restore-down
```

`--archive-mode=off` **no es opcional**: sin él el cluster restaurado hereda el `archive_command` del backup y empieza a empujar WAL a la stanza de producción. Es la misma protección que `PG_ARCHIVE_MODE`, en el otro extremo del proceso.

```bash
echo "# 7 → Sembrar el filestore, del snapshot más nuevo que la base"
make restore-up
docker compose exec restore-files restic restore latest --target / --include /data/odoo
make restore-down
```

`--include /data/odoo` acota el restore a lo único que este contenedor monta: el snapshot trae también `/data/meta`, y restic —que corre acá con el uid de Odoo— no puede crear ese directorio en la raíz del contenedor, así que sin el filtro termina con error.

El orden importa y es el inverso al del backup: un filestore **más nuevo** que la base deja archivos huérfanos, inofensivos; uno más viejo deja filas de `ir_attachment` apuntando a archivos que no existen.

```bash
echo "# 8 → Levantar el stack completo"
make up
```

**Verificación.**

```bash
echo "# 9 → Estado de las capas que este stack sí tiene"
make verify
```

Las capas ausentes salen como `--`, no en rojo: backups y observabilidad omitidas enteras, `dnsmasq` y `cloudflared`… — el que no esté, se nombra. Lo que **sí** tiene que pasar es `archive_mode APAGADO`, el certificado vigente y las tres rutas de Odoo en nginx.

```bash
echo "# 10 → Los adjuntos que la base referencia están en el filestore"
scripts/integrity-check.sh
```

Salida esperada `referenciados: N | faltantes: 0`. Cada línea `FALTA:` es un adjunto roto, y significa que el snapshot de restic elegido es **anterior** al punto de la base.

```bash
echo "# 11 → Ejercitar la renovación ANTES de que producción dependa de ella"
scripts/cert.sh renew --force-renewal
```

Es el único paso de esta fase que no es para staging sino **para producción**: fuerza una emisión real, el reload de nginx y la escritura de la métrica de vencimiento, que es toda la cadena que el timer va a correr sola dentro de sesenta días. Si algo de eso está roto, el modo de falla es silencioso — el certificado vence y nadie se entera.

- [ ] `make verify` sale con exit `0`
- [ ] `https://<hostname de staging>` sirve con certificado de Let's Encrypt
- [ ] El chat en vivo actualiza sin refrescar — es lo que prueba el `location /websocket`
- [ ] `integrity-check.sh` sin faltantes
- [ ] La renovación forzada terminó con nginx sirviendo el certificado nuevo

Refrescar staging más adelante es repetir los bloques 6 a 8. Cada vez es otro simulacro de restore.

## 11. Desarrollo

**Objetivo.** Un checkout por feature en tu máquina, con Odoo sirviendo por nginx en loopback. Sin túnel, sin certificados, sin backups y **sin ningún valor que pegar a mano**: los tres secrets se generan.

nginx está aunque no haya TLS. Es lo que hace honesto al `proxy_mode = True` de `odoo.conf`: sin nadie escribiendo `X-Forwarded-*`, Odoo confía en cabeceras que no existen, y esa diferencia con producción aparece justo en lo que es difícil de reproducir.

**A mano.** Nada. Dos decisiones, las dos en `.env`:

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | `development-<feature>`, **único por checkout** |
| `COMPOSE_FILE` | `compose.dev.yaml` |
| `PG_ARCHIVE_MODE` | `off` |
| `HTTP_PORT` | El puerto de loopback, distinto por checkout si vas a alternar |
| `ADDONS_BRANCH` | Tu rama de trabajo |

> **El nombre del proyecto es el único aislamiento entre dos checkouts de desarrollo.** De él salen los volúmenes: dos que lo compartan resuelven al mismo `pgdata`, y como corre uno a la vez no colisionan al arrancar — **se pisan los datos en silencio**, que es precisamente lo que un entorno por feature viene a evitar. Si falta la clave, Compose usa el nombre del directorio, que ya es único; el caso peligroso es copiar el `.env` de un checkout a otro.

`NGINX_MODE` **no se declara**: `compose.dev.yaml` fija la plantilla sin TLS en el entrypoint, para que un `.env` sin la clave no deje a nginx buscando un certificado que nadie emitió.

**Comandos.**

```bash
echo "# 1 → Un directorio por feature, con su nombre adentro"
FEATURE='sale'
git clone "$REPO_URL" ~/odoo-development-$FEATURE && cd ~/odoo-development-$FEATURE
```

Acá **no** se fija a un tag: el checkout de desarrollo sigue la rama en la que estás trabajando. El `HEAD` detached es un guard-rail del servidor, donde nadie debería estar corrigiendo código.

```bash
echo "# 2 → Config: las cinco claves de la tabla; COMPOSE_FILE ya viene puesto"
cp .env.dev.example .env
${EDITOR:-vi} .env
```

**Antes de `secrets-init`, no después.** El script deriva de `COMPOSE_FILE` qué secrets lleva el stack, y nunca pisa un archivo existente: un secret creado de más queda pidiendo un valor que development no usa, para siempre. La plantilla trae el `COMPOSE_FILE` correcto, pero el `COMPOSE_PROJECT_NAME` **hay que editarlo igual**: el placeholder es el mismo para todo checkout que no lo cambie, y de ahí salen los volúmenes.

```bash
echo "# 3 → Los 3 secrets, todos generados"
make secrets-init
sudo make secrets-perms
```

`secrets-init` no imprime ningún pendiente: los tres salen de `openssl`. `secrets-perms` sigue necesitando root — deja cada archivo en `640` con el grupo del proceso no-root que lo lee, y ese GID no es tuyo.

```bash
echo "# 4 → Árbol de addons de tu rama, e imagen"
set -a; . ./.env; set +a
make addons-sync
docker compose build
```

```bash
echo "# 5 → Levantar"
make up
```

La base arranca vacía: el entrypoint detecta que no está inicializada y corre `-i base` contra `postgres:5432`, no contra PgBouncer. La primera vez tarda.

**Verificación.**

```bash
echo "# 6 → Estado, y el sitio por el proxy"
make verify
curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:${HTTP_PORT:-8080}/web/login"
```

Tiene que dar `200`. `make verify` omite el certificado, el `server_name` y el 443 —los tres derivados de que este stack sirve en texto plano, y los deduce de la composición, no de una variable—, y avisa en vez de fallar si tu `ADDONS_BRANCH` no lleva la versión en el nombre: de una rama `feat/*` no se puede afirmar que sea de la misma versión que la imagen.

El aislamiento entre checkouts se comprueba una sola vez, con dos clonados:

```bash
echo "# 7 → Desde el segundo checkout, con el primero levantado"
docker volume ls --format '{{.Name}}' | grep '^development-'
```

Tiene que haber un juego de volúmenes por nombre de proyecto —`development-sale_pgdata`, `development-accountant_pgdata`— y ninguno compartido. Si ves uno solo para los dos, los `COMPOSE_PROJECT_NAME` son iguales y las dos bases son la misma.
