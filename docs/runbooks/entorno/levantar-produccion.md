# Levantar producción

## Cuándo se usa

Puesta en marcha de un deploy de producción nuevo, de punta a punta — desde las cuentas externas hasta el sistema listo para recibir el primer dato real de un usuario. Nueve fases, en orden: cada una depende de que la anterior haya cerrado.

Para levantar un segundo entorno sobre un stack de producción ya operativo, ver [levantar-staging](levantar-staging.md) y [levantar-desarrollo](levantar-desarrollo.md) — los dos reusan buena parte de lo que se decide acá (identidad del stack, secrets, addons) pero son procedimientos propios, no continuaciones de este.

## Objetivo

Once servicios corriendo, verificados capa por capa, con el certificado real, los backups probados una vez de punta a punta y las alertas llegando por mail. El deploy termina en el primer dato que carga un usuario — todo lo anterior es descartable.

## Prerrequisitos del servidor

| Requisito | Por qué |
|---|---|
| Docker Engine y Compose ≥ 2.20, habilitados al arranque | Lo exige la directiva `include:` de `docker/compose.yaml`; sin arranque automático el stack no vuelve tras un reinicio |
| Rotación de logs del daemon, configurada **antes** del primer contenedor | Solo aplica a contenedores creados después de reiniciar el daemon. Hacerlo más tarde obliga a recrear los once (`config/docker/daemon.json`) |

**El firewall del host no protege a los contenedores.** Docker publica por DNAT e inserta sus reglas antes de las cadenas del firewall: un `deny` no alcanza a un puerto publicado por un contenedor. El aislamiento de cada servicio es la IP a la que se publica, y eso ya está resuelto en los `docker/compose.*.yaml`.

`make host-verify` (fase 2, más abajo) valida estos dos prerrequisitos junto con el resto de la config del repo.

---

## Fase 1 — Cuentas externas

### Objetivo

Seis cuentas creadas, las dos passphrases custodiadas, y en la mano todos los valores que carga la fase 2.

### A mano

**Primero la zona, y ya:** creá tu dominio en Cloudflare y **delegá el DNS** apuntando los nameservers en el registrador. Puede tardar 48h, y la verificación del dominio de envío de ZeptoMail escribe SPF/DKIM ahí, así que no arranca hasta que propague. Esas dos encadenadas son el camino crítico de toda la instalación. El resto son minutos, en cualquier orden.

| Cuenta | Qué crear | Dónde termina |
|---|---|---|
| Cloudflare — zona | Tu dominio, con el DNS **delegado** en el registrador | — |
| Cloudflare — API token | Plantilla **Edit zone DNS** sobre la zona. Con `Zone:DNS:Edit` a secas falla `403 9109` y el cert no se emite nunca | `secrets/cloudflare_api_token` |
| Cloudflare Zero Trust | Un Tunnel (Networks → Tunnels) | `secrets/cloudflare_tunnel_token` |
| Cloudflare R2 | Bucket nuevo y vacío —uno solo, conviven `pgbackrest/` y `restic/`— y token `Object Read & Write` acotado a él | `secrets/pgbackrest_r2_credentials` · `secrets/restic_r2_credentials` · `R2_ENDPOINT` (sin esquema) · `R2_BUCKET` |
| ZeptoMail | Dominio verificado, Mail Agent, y saldo — sin créditos la alerta se detecta pero no sale | `secrets/zeptomail_smtp_password` · `SMTP_USER` · `ALERT_EMAIL_FROM` |
| Git remoto (GitHub, GitLab…) | Token de solo lectura sobre la organización donde viven tus repos de addons. Anotá el vencimiento si es de los que expiran | `~/.git-credentials` del servidor (fase 5) y de tu máquina ([levantar-desarrollo](levantar-desarrollo.md)) |

### Comandos

Las dos passphrases de cifrado se inventan acá. Mismo comando, **dos valores distintos**: cifran repositorios separados y terminan en archivos separados. Hex y no base64: los `/ + =` rompen a cualquier consumidor que arme una URI con la credencial adentro.

```bash
echo "# 1 → Passphrase de pgBackRest, a secrets/pgbackrest_r2_credentials"
openssl rand -hex 32
```

```bash
echo "# 2 → Passphrase de restic, a secrets/restic_password (valor distinto)"
openssl rand -hex 32
```

> **Al gestor de contraseñas ahora, antes de seguir.** Perderlas deja el repositorio de backups irrecuperable — no hay procedimiento. Y no las dejes solo en el servidor: si el servidor es lo que se perdió, ahí no las vas a poder buscar. Mismo trato para el token de R2, que puede vaciar el bucket (R2 no tiene versioning). Una vez guardadas, cerrá la terminal: a diferencia de los tokens, estas dos sí quedan impresas en el scrollback.

### Verificación

Todavía no hay repo clonado, así que los valores van en una línea de asignación. Dos de las seis cuentas se pueden probar de verdad ahora, y son las que más tarde muerden.

```bash
echo "# 3 → Completá tu zona"
ZONA='ejemplo.com'
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
```

```bash
echo "# 7 → Token del Mail Agent (pegalo y Enter, no se muestra)"
read -rs ZM_TOKEN && printf 'From: %s\nTo: %s\nSubject: prueba\n\nok\n' "$ZM_FROM" "$ZM_TO" \
  | curl -sS --ssl-reqd --url smtp://smtp.zeptomail.com:587 \
      --user "$ZM_USER:$ZM_TOKEN" --mail-from "$ZM_FROM" --mail-rcpt "$ZM_TO" --upload-file - \
  && echo "OK: aceptado por ZeptoMail — confirmá que llegó a $ZM_TO"
```

`ZM_USER` **no es tu dirección de correo**: sale de ZeptoMail → Mail Agents → el agente → SMTP & API, donde figura el `Username` literal (suele ser `emailapikey`). Y el token va **sin el prefijo `Zoho-enczapikey`**, que es para el header HTTP de la API, no para SMTP.

Ese usuario es el que después va a `SMTP_USER` en `.env` y el que usa `scripts/failure-notify.sh` en la fase 7: acertarlo acá evita que el aviso de backup fallido falle en silencio más adelante.

En los dos bloques con token, el `read` va en el último comando y lo que usa el valor cuelga del mismo `&&`: si quedara una línea suelta debajo, `read` se la comería como valor y el `curl` no correría — sin error y sin salida.

Lo que no se puede probar todavía: el token del Tunnel (fase 3), R2 (fase 4) y el del git remoto (fase 5).

---

## Fase 2 — El repositorio

### Objetivo

El repo clonado en el último release, con `.env` y los 11 secrets cargados y validados. Nada levantado todavía.

### A mano

`secrets-init` deja **11 archivos**: 5 generados que no se tocan nunca —`postgres_password`, `pgbouncer_credentials`, `odoo_admin_password`, `grafana_admin_password`, `postgres_exporter_password`— y 6 con el marcador `CAMBIAR`, que se llenan con lo que juntaste en la fase 1. Tres detalles de formato:

- `cloudflare_api_token`: sin comillas y **sin salto de línea final** — `nano -L`. Cloudflare emite dos formatos según cuándo lo creaste: 40 caracteres el viejo, `cfut_...` (~46) el nuevo — los dos son válidos.
- `pgbackrest_r2_credentials` y `restic_r2_credentials` ya vienen con su esqueleto INI. **La misma clave de R2 va en los dos**, en sintaxis distinta: al rotarla hay que tocar ambos (ver [rotar-credenciales-r2](../credenciales/rotar-credenciales-r2.md)).
- Editor interactivo, nunca `echo >>`: así el token no queda en el historial.

En `.env`, seis claves que la fase 1 no cubre. Las otras cuatro (`R2_ENDPOINT`, `R2_BUCKET`, `SMTP_USER`, `ALERT_EMAIL_FROM`) salen de su tabla.

| Clave | Valor |
|---|---|
| `COMPOSE_PROJECT_NAME` | Nombre del stack: `production` acá. Gobierna contenedores, volúmenes, redes y tags de imagen |
| `COMPOSE_FILE` | `docker/compose.yaml` para producción |
| `PUBLIC_HOSTNAME` | El hostname público de esta instancia, el mismo que va a servir el Tunnel |
| `LOCAL_IP` | La IP LAN del servidor — real y de una interfaz existente: `dnsmasq` bindea exactamente ahí y si no, queda `unhealthy` |
| `PGBACKREST_STANZA` | Nombre de la stanza, estable — cambiarlo deja huérfanos los backups viejos |
| `ALERT_EMAIL_TO` | Destinatario de los avisos de backup y de las alertas de Grafana |

### Comandos

```bash
echo "# 1 → Completá la URL de tu fork"
REPO_URL='git@github.com:tu-organizacion/infrastructure-odoo.git'
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
echo "# 4 → IPs del servidor — anotá las dos primeras, las piden las fases 3 y 6"
echo "LAN:     $(hostname -I | awk '{print $1}')"
echo "Pública: $(curl -s ifconfig.me)"
```

`LAN` va a `LOCAL_IP` y tiene que caer en tu subred local: si sale una IP de tu VPN o de un bridge de Docker, agarró la interfaz equivocada. Anotá además la IP por la que administrás el servidor — la de tu VPN —, que la usan los túneles SSH de las fases 3 y 8.

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

### Verificación

```bash
echo "# 7 → Prerrequisitos del servidor y config del repo"
make host-verify
```

Cubre versión de Compose, arranque automático de Docker, `.env` sin claves vacías, la identidad declarada del stack, permisos y GID de los 11 secrets, y la superficie publicada del host.

---

## Fase 3 — Borde

### Objetivo

El certificado emitido, nginx sirviendo con él, el Tunnel conectado y `dnsmasq` resolviendo el hostname a la IP local para la LAN.

**El orden importa y es al revés de lo intuitivo: primero el certificado, después el proxy.** nginx no arranca si el archivo del certificado no existe, y con DNS-01 certbot no necesita que nginx esté vivo para emitirlo — valida contra la API de Cloudflare, no contra el puerto 80.

### A mano

El **Public Hostname del Tunnel**, en Zero Trust → Networks → Tunnels → el Tunnel → Public Hostname. Va a mano porque el Tunnel es *remotely-managed*: no hay archivo de este repo que lo reemplace.

| Campo | Valor |
|---|---|
| Subdomain + Domain | Los que componen tu `PUBLIC_HOSTNAME` |
| Service | `https://nginx:443` — comparten la red `edge`, se resuelven por nombre |
| TLS → **Origin Server Name** | Tu `PUBLIC_HOSTNAME` completo — el que se olvida |
| TLS → No TLS Verify | desactivado |

**El campo Origin Server Name vacío no se ve vacío.** El dashboard le pone de placeholder la palabra `Null` en gris, que a simple vista se confunde con un valor ya cargado. Si no lo ves escrito en texto negro, no está seteado.

Sin Origin Server Name, `cloudflared` cae al hostname del propio Service (`nginx`) para validar el certificado, que no es a quién se lo emitió Let's Encrypt, y el sitio entero da **502**. No se manifiesta acá: recién en la fase 6, con Odoo sirviendo tráfico real. El error, en `docker compose logs cloudflared`, es inconfundible:

```
tls: failed to verify certificate: x509: certificate is valid for <tu PUBLIC_HOSTNAME>, not nginx
```

### Comandos

```bash
echo "# 1 → Emitir el certificado (one-off; nginx todavía no existe)"
make cert-issue
```

```bash
echo "# 2 → Levantar el borde (dnsmasq se construye la primera vez)"
docker compose up -d cloudflared nginx dnsmasq
```

**El hostname público va a dar 502 al terminar esta fase, y está bien.** nginx ya sirve con el certificado real, pero su upstream —Odoo— no existe hasta la fase 6.

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

**El que importa es el 4b.** Si el 4a da la IP local y el 4b devuelve una IP de Cloudflare, `dnsmasq` está sano y no lo usa nadie: quién resuelve para la LAN lo decide el DHCP del router, no este repositorio.

```bash
echo "# 5 → Desde fuera de la LAN (datos móviles): tiene que fallar"
SRV_PUB='ip-publica-del-servidor'
nc -z -w2 "$SRV_PUB" 443 && echo "MAL: el router está reenviando el 443" || echo "OK: sin reenvío"
```

nginx no publica ninguna UI. Su estado se lee del log (JSON, `docker compose logs nginx`) y de `make edge-verify`.

---

## Fase 4 — Datos

### Objetivo

La base corriendo y **ya respaldándose**, antes de que exista un solo dato adentro.

### A mano

Ninguno. La única decisión de esta fase es de orden, explicada abajo.

### Comandos

```bash
echo "# 1 → Levantar la base y el pooler (postgres se construye la primera vez)"
docker compose up -d postgres pgbouncer
```

El rol `odoo` y su password son **definitivos** — la fase 6 reusa esa misma credencial sin rotarla.

```bash
echo "# 2 → Crear la stanza y probar el archivado hasta R2"
docker compose exec -T -u postgres postgres pgbackrest stanza-create
docker compose exec -T -u postgres postgres pgbackrest check && echo "OK: el archive_command llega a R2"
```

**Va acá y no en la fase 7, y la ventana tiene que ser cero.** Postgres arranca con `archive_mode = on`, así que cada archivado falla hasta que la stanza exista y los WAL se acumulan en `pg_wal`. `check` fuerza un switch de WAL y lo sigue hasta R2 — es también donde se prueba por primera vez la credencial de R2. Si falla acá, mirá el endpoint (va sin esquema), el bucket y la clave.

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

## Fase 5 — Addons

### Objetivo

El árbol de módulos en disco y la imagen de Odoo construida. La fase 6 no arranca sin esto: el entrypoint aborta si el `addons_path` queda vacío.

### A mano

`addons/addons.txt` no existe todavía. Se bootstrapea desde su plantilla y se completa con tus repos, uno por línea (`URL categoría`) — al menos el que provee `bus_alt_connection` (obligatorio), aunque no tengas módulos propios todavía; si no tenés ninguno, forkealo primero (ver [crear-fork](../modulos/crear-fork.md)).

Segundo, el token de la fase 1, que se pega abajo. Lo piden los repos privados del manifiesto; los forks públicos no. No es un secret de Compose: el clonado ocurre en el host y ningún contenedor lo consume.

### Comandos

```bash
echo "# 1 → Bootstrapear el manifiesto y los pines desde sus plantillas"
cp addons/addons.txt.example addons/addons.txt
cp addons/requirements.txt.example addons/requirements.txt
${EDITOR:-vi} addons/addons.txt
```

```bash
echo "# 2 → Completá tu usuario y el host HTTPS de los repos de addons — no un alias SSH propio"
GIT_USER='tu-usuario'; GIT_HOST='github.com'
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

```bash
echo "# 5 → Construir la imagen de Odoo"
docker compose build odoo && echo "OK: imagen construida"
```

**El build no clona nada.** Instala las dependencias Python de `addons/requirements.txt` si el archivo existe —lo escribe `make pydeps-sync`, no se versiona— y copia el entrypoint, nada más. La consecuencia buscada: desplegar un cambio de módulo no vuelve a requerir un rebuild.

### Verificación

```bash
echo "# 6 → Estado de cada worktree"
make addons
```

Encabeza con la rama declarada y sigue con una fila por repo del manifiesto, todas en `limpio`. Un `(sin worktree)` o un `sucio` es un sync incompleto. Si un repo privado falló con `Repository not found` o `Authentication failed`, el token no tiene los permisos justos: alcanza con lectura de contenidos sobre tu organización.

Es un chequeo visual: `make odoo-verify` lo vuelve a validar mecánicamente en la fase siguiente.

---

## Fase 6 — Aplicación

### Objetivo

Odoo sirviendo por el hostname público con certificado propio de Let's Encrypt. Acá se cierra el 502 que dejó la fase 3.

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

Solo Cloudflare agrega `server:` y `cf-ray:`. Un `200` sin ellos significa que el pedido nunca salió a internet. Si en cambio da 502, confirmá el Origin Server Name de la fase 3.

```bash
echo "# 5 → Rate-limit del login: diez 400 y después 503"
for i in $(seq 1 20); do curl -sk -o /dev/null -w "%{http_code} " -X POST \
  --resolve "$PUBLIC_HOSTNAME:443:$LOCAL_IP" "https://$PUBLIC_HOSTNAME/web/login"; done; echo
```

El `400` es Odoo rechazando un POST sin token CSRF — válido, no un fallo; lo que se mide es el corte en el 11.º, que `limit_req` devuelve como 503. Va directo a nginx por `--resolve` a propósito: con la latencia de Cloudflare de por medio el corte no aparece nunca.

**Y el chatter, con dos sesiones abiertas:** mandá un mensaje y confirmá que aparece solo, sin recargar. Prueba que nginx rutea `/websocket` al worker gevent (`8072`), y que `bus_alt_connection` está activo — sin él, el modo transacción de PgBouncer rompe el `LISTEN/NOTIFY` del bus.

---

## Fase 7 — Protección

### Objetivo

Las dos mitades del backup corriendo, probadas una vez de punta a punta, y avisando por mail si fallan.

### A mano

Ninguno. Como en la fase 4, lo único propio es el orden: va después de la 6 porque su verificación exige un snapshot, y un snapshot exige que exista un filestore.

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

## Fase 8 — Observación

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

## Fase 9 — Puesta en producción

### Objetivo

El sistema listo para recibir datos, con todo lo que los protege ya corriendo **y ya probado una vez**. El punto de no retorno real no es el `-i base` de la fase 6 —esa base es descartable— sino el primer dato que carga un usuario.

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
- [ ] Hay un snapshot de restic y un `full` de pgBackRest de la corrida de la fase 7
- [ ] Llegó el mail de prueba del contact point de Grafana
- [ ] El simulacro de restore semestral está agendado y leído una vez
- [ ] Las dos passphrases de cifrado están en el gestor de contraseñas, **fuera del servidor**

La última no es ceremonia: es lo único de esta lista que, si falta, no se puede arreglar después.

A partir de acá, la operación normal está repartida en [operacion/](../operacion/), [modulos/](../modulos/), [backup-restore/](../backup-restore/) y [credenciales/](../credenciales/).
