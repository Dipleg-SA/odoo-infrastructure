# Troubleshooting

Síntoma → causa → fix, agrupado por stack en el mismo orden que [`INSTALL.md`](../INSTALL.md). Este documento se lee cuando algo ya se rompió; el runbook de instalación se lee una vez y no debería tener que releerse para diagnosticar.

Cada entrada arranca con el **síntoma observable** (lo que ves, no lo que pasa por debajo), porque es el único dato con el que contás cuando empezás a buscar.

## Nota previa — desarrollo local en macOS

Docker Desktop en macOS **no respeta fielmente los permisos POSIX** en archivos bind-mounted owned-por-root: incluso `root` dentro de un contenedor puede recibir `Permission denied` leyendo un archivo que `stat` muestra como legible. Es una limitación de su capa de virtualización (gRPC-FUSE/VirtioFS), no un bug de los scripts de este repo — verificado que el mismo mecanismo funciona correctamente en el servidor Linux real.

Si algo relacionado a permisos se comporta raro en Mac, descartá esto **antes** de asumir que la lógica de compose o de los scripts está mal.

## Networking / Edge

**`dnsmasq` no bindea o no resuelve.** Corre en `network_mode: host` (no publica puerto vía Docker), escuchando directo en `${LOCAL_IP}:53` (`--listen-address` + `--bind-interfaces`). Dos motivos, ambos surgidos en el primer deploy real:

- **systemd-resolved (Ubuntu):** un bind wildcard `0.0.0.0:53` choca con su stub listener en `127.0.0.53:53` (`failed to bind host port ...:53/udp: address already in use`). Al escuchar solo en `${LOCAL_IP}` no se solapa.
- **Reachability con `ufw`:** un publish de Docker a una IP específica (UDP) no llegaba al contenedor a través del NAT/FORWARD con `ufw` en `deny (routed)`. Como proceso del host, el tráfico entra por INPUT, donde la regla de `ufw` sí lo permite.

Requiere que el firewall del host permita el `53/udp` desde la subred LAN en INPUT — es un prerrequisito del servidor, no un paso del runbook (ver «Prerrequisitos del servidor» en `INSTALL.md`). Con `ufw`:

```bash
sudo ufw allow from <subred-lan>/24 to any port 53 proto udp
```

Diagnóstico: `sudo ss -ulnp | grep ':53'` debe mostrar `dnsmasq` escuchando en `${LOCAL_IP}:53`. El test real es **desde un dispositivo de la LAN** (`dig <PUBLIC_HOSTNAME> @${LOCAL_IP}`), no desde el propio servidor — el host consultándose a sí mismo puede dar timeout por NAT sin que sea un problema real.

**nginx no arranca: `cannot load certificate`.** Es el orden invertido, no una falla. nginx se niega a levantar si el archivo del certificado no existe, y quien lo emite es certbot. En un deploy nuevo el certificado va **antes** del primer `up`:

```bash
make cert-issue
```

Con DNS-01 no hace falta que nginx esté vivo para emitir: la validación va contra la API de Cloudflare, no contra el puerto 80.

**nginx `unhealthy`.** Su healthcheck es `nginx -t`, así que un `unhealthy` es siempre config inválida. El log dice la línea:

```bash
docker compose logs --tail=20 nginx
```

La causa más común en un deploy nuevo es que la sustitución de variables no corrió y quedó el literal `${PUBLIC_HOSTNAME}` dentro de la config. Se ve directo:

```bash
docker compose exec nginx grep -r '\${' /etc/nginx/conf.d/
```

Cualquier resultado ahí es un `envsubst` que no sustituyó: revisá que la variable esté en `.env` y que `NGINX_ENVSUBST_FILTER` en `compose.proxy.yaml` la cubra. Lo chequea también `make edge-verify`.

**`cloudflared` no conecta.** El token del Tunnel pegado en `secrets/cloudflare_tunnel_token` está mal copiado o expiró, o hay egress bloqueado hacia Cloudflare desde el servidor.

**502 "Bad gateway" de Cloudflare con todos los servicios `healthy`.** El stack interno anda; lo que falla es la identidad TLS del origen. El log de `cloudflared` dice qué nombre esperaba:

```bash
docker compose logs --tail=20 cloudflared | grep -o 'error="[^"]*"' | sort -u
```

- **`x509: certificate is valid for <tu PUBLIC_HOSTNAME>, not nginx`** → el **Origin Server Name está vacío** en el Public Hostname del Tunnel. `cloudflared` valida el certificado contra el nombre del servicio (`nginx`), que no es el del certificado. Se arregla **solo en el dashboard** (Zero Trust → Networks → Tunnels → el Tunnel → Public Hostname → Additional application settings → TLS → Origin Server Name = `$PUBLIC_HOSTNAME`). `cloudflared` recarga solo, sin restart: confirmalo con `docker compose logs --tail=5 cloudflared | grep "Updated to new configuration"`, que debe mostrar `"originServerName":"<tu PUBLIC_HOSTNAME>"`.
- **`x509: certificate signed by unknown authority`** → el certificado salió del entorno de staging de Let's Encrypt, que no es confiable para `cloudflared`. Revisá que `make cert-issue` no lleve `--staging` y reemití.

**502 justo después de recrear Odoo, con nginx sano.** Es el caché de resolución de nginx: resuelve los upstream al arrancar y se queda con la IP vieja. El repositorio lo previene con `resolver 127.0.0.11 valid=10s` y `proxy_pass` a través de una variable, que es lo que obliga a reconsultar; si alguien reescribe la location con el nombre fijo (`proxy_pass http://odoo:8069`), el síntoma vuelve. Lo chequea `make edge-verify`. Mitigación inmediata:

```bash
docker compose exec nginx nginx -s reload
```

**La emisión del certificado falla.** El log de certbot nombra la causa:

```bash
docker compose --profile cert run --rm certbot certificates
```

`[status code 403] 9109` o similar contra la API de Cloudflare significa que el token de `secrets/cloudflare_api_token` no sirve. Cuál de las dos variantes es, sin exponerlo en `ps` (`printf` es builtin):

```bash
printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/user/tokens/verify"\n' "$(sudo cat secrets/cloudflare_api_token)" | curl -s --config -
```

- `code 1000 "Invalid API Token"` → el valor está mal pegado. Confirmalo con `sudo wc -c < secrets/cloudflare_api_token`: son **40 bytes sin salto de línea**. Cualquier otro número es un token truncado, con basura alrededor, o directamente otra credencial.
- `"status":"active"` (y el `9109` solo contra `/zones`) → el token vive pero no puede leer la zona. Le falta `Zone:Read`: rehacelo con la plantilla **Edit zone DNS**.

Si la emisión falla por **validación** y no por credencial, subí `ACME_PROPAGATION_SECONDS` en `.env`: certbot está pidiendo la verificación antes de que el registro TXT haya propagado.

Para aislar en qué eslabón está el problema, un contenedor descartable en la red `edge` (`cloudflared` es distroless, no tiene shell propia):

```bash
docker run --rm --network "$(docker compose config | awk '/^name:/{print $2}')_edge" curlimages/curl -sk -o /dev/null -w "%{http_code}\n" https://nginx:443 -H "Host: $PUBLIC_HOSTNAME"
```

Si eso da `303`/`200`, nginx y Odoo están bien y el problema es exclusivamente TLS entre `cloudflared` y nginx — o sea, una de las causas de arriba.

**Ruido en los logs de `cloudflared`.** Pedidos a `/actuator/env`, `/info.php`, `/config.json`, `/.env`, rutas de Jira/WordPress. Son bots escaneando el hostname público, aparecen desde que el DNS queda expuesto. No es un compromiso; no hace falta actuar. Al contar errores conviene acotar la ventana (`--since 5m`) para no mezclarlos con fallas viejas ya resueltas.

**El certificado no se renueva.** La renovación no vive en ningún contenedor: la corre el timer `odoo-cert-renew.timer`, dos veces por día. Si el certificado se acerca al vencimiento, lo primero es el timer:

```bash
systemctl list-timers odoo-cert-renew.timer
journalctl -u odoo-cert-renew.service -n 30
```

Un fallo manda mail por el `OnFailure=`, igual que los backups. Y hay un caso que el timer **no** cubre y la alerta tampoco: que certbot renueve bien y nginx siga sirviendo el certificado viejo porque nadie lo recargó. `scripts/cert.sh renew` hace el reload como parte de la corrida; si tenés que forzarlo:

```bash
docker compose exec nginx nginx -s reload
```

La métrica `odoo_cert_expiry_timestamp_seconds` la escribe ese mismo script en `state/textfile/`, y de ahí la levanta Alloy. Mide lo que certbot tiene en disco, no lo que nginx está sirviendo — por eso el reload importa.

Let's Encrypt dejó de mandar avisos de vencimiento el 2025-06-04, así que la vigilancia es activa: la alerta `cert-por-vencer` dispara a los 21 días restantes, ~9 días después de que la renovación automática debió correr, y cubre también que la métrica no exista, porque sin serie la regla alerta igual.

## Capa de datos

**`postgres`/`pgbouncer` `unhealthy`.** Causas típicas: permisos incorrectos en `pgbouncer_credentials` (si estás probando en Mac en vez del servidor real, ver la nota previa sobre macOS), el archivo no tiene el formato exacto `"odoo" "password"` (comillas incluidas), o el puerto ya está ocupado por otra instancia de Postgres en el host.

## Odoo core

**El entrypoint falla al arrancar.** Causas típicas: GID incorrecto en `odoo_admin_password`/`zeptomail_smtp_password` — deben ser `101`, y se arregla con `sudo make secrets-perms && make secrets-check` (el mapa vive en `scripts/secrets-perms.sh`, no en el runbook); Postgres/PgBouncer todavía no están `healthy` cuando Odoo intenta conectar (confirmar que `make db-verify` pasa antes de arrancar Odoo); o el `addons_path` quedó **vacío** y el entrypoint aborta a propósito (`addons_path vacío — ¿corriste make addons-sync...?`), que Desde el paso a bind-mount, es la causa más frecuente: los addons llegan por bind-mount desde `addons/`, así que su presencia ya no la garantiza la imagen — se arregla con `make addons-sync`, y si eso falla por credencial, el PAT vive en `~/.git-credentials` del host (ver `docs/addons.md`).

## Backups y DR

**`unable to restore while PostgreSQL is running` con Postgres ya detenido.** Quedó un `postmaster.pid` de un apagado sucio. La imagen usa `STOPSIGNAL SIGINT` (fast shutdown), pero con Odoo y PgBouncer conectados no alcanza a cerrar en los 10s por defecto y Docker lo mata. Se resuelve parando con timeout: `docker compose stop -t 60 postgres`. Confirmar que el pid file no está antes de reintentar.

**El WAL se acumula en `pg_wal` (archivos `.ready` que crecen).** El archivado está roto y el disco de la base se va a llenar. Causas típicas: credencial de R2 vencida o mal rotada, `PGBACKREST_STANZA` vacío en `.env`, o el bucket inalcanzable. Diagnóstico: `docker compose exec -u postgres postgres pgbackrest check`. Los backups full/diff pueden seguir aparentando éxito mientras esto pasa — por eso `check` corre primero en cada corrida diaria.

**Un secret rotado no surte efecto, o el contenedor reporta `No such file`.** Los secrets son bind-mounts de **archivo**, atados al inode. Editarlos con algo que reemplace el archivo (`sed -i`, varios editores) desvincula el inode montado. El contenedor queda viendo el archivo viejo o ninguno, y **restaurar el contenido no lo arregla**. Solución: `docker compose up -d --force-recreate <servicio>`. Verificar además el GID con `make secrets-check`: si la herramienta recreó el archivo, probablemente también perdió el grupo.

**`unable to find primary cluster` en `stanza-create`.** pgBackRest se conecta a la base como rol `postgres`, que en este cluster no existe (se creó con `POSTGRES_USER=odoo`). El rol correcto llega por `PGBACKREST_PG1_USER` desde `compose.db.yaml`; si el error aparece, es que esa variable no está en el entorno del contenedor.

**`unable to verify certificate presented by ...r2.cloudflarestorage.com`.** Falta el almacén de CAs raíz. La imagen oficial de Postgres no trae `ca-certificates`; el `docker/postgres/Dockerfile` lo instala. Si aparece, la imagen en uso no es la propia: `docker compose build postgres && docker compose up -d postgres`.

**El contenedor `backup` dice `starting` y no pasa a `healthy`.** Con `interval: 1h` el primer chequeo tarda hasta una hora tras cada reinicio, y durante el `start_period` de 5m los fallos no cuentan. **No es un fallo.** Para ver el estado real sin esperar:

```bash
docker inspect -f '{{range .State.Health.Log}}{{.ExitCode}} {{end}}' $(docker compose ps -q backup)
```

**`restic forget` no borra lo que se espera.** La política se aplica **por grupo `(host, paths)`**. Si una corrida respaldó un path distinto, forma su propio grupo y `keep-daily` lo conserva aunque sea viejo. Con el script estándar no pasa (siempre el mismo path), pero explica resultados raros si alguien corrió un `restic backup` manual sobre otra ruta.

## Observability

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `cadvisor` emite series sin etiqueta `name` | Alloy no alcanza el socket de containerd | Verificar el montaje `/run/containerd/containerd.sock:ro`; sin él no enumera contenedores y las métricas por contenedor quedan anónimas |
| Alertas `DatasourceNoData` en vez de la alerta real | Una expresión que devuelve vector vacío en el estado sano | Las siete reglas ya están escritas para devolver siempre valor; si agregás una, no uses `metrica == 0` como consulta |
| La alerta de disco nunca dispara | Filtro por `mountpoint` que no existe en ese host | La regla filtra por `fstype` justamente para no depender del nombre del punto de montaje |
| Un segundo servicio caído tarda ~5 min extra en avisar | Agrupación de notificaciones demasiado amplia | Ya se agrupa por `alertname, job, name`; si se cambia a solo `alertname`, se pierde el techo de 5 minutos |
| Grafana no lee un secret | Su gid primario es 0, no 472 | El acceso llega por `group_add: ["472","101"]`; si se sacan, no lee ni su contraseña de admin ni la de SMTP |
| El exporter de Postgres no conecta | La password del rol y la del archivo se desincronizaron | Rotar el secret **no** cambia la base: hace falta `ALTER ROLE monitoring PASSWORD` (ver la fase «Observación» de `INSTALL.md`) |
| Un contenedor no rota sus logs (`LogConfig` vacío) | Es anterior al restart del daemon | La rotación de `daemon.json` solo aplica a contenedores creados después; `docker compose up -d --force-recreate <servicio>` |
