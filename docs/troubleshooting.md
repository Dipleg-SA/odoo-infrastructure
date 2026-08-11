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

**Traefik `unhealthy`.** Causas típicas, en orden de probabilidad: zona `<tu-dominio>` no delegada realmente a Cloudflare (Prerrequisitos), o el token de API sin el permiso `Zone:DNS:Edit` correcto.

**`cloudflared` no conecta.** El token del Tunnel pegado en `secrets/cloudflare_tunnel_token` está mal copiado o expiró, o hay egress bloqueado hacia Cloudflare desde el servidor.

**502 "Bad gateway" de Cloudflare (Host → Error) con todos los servicios `healthy`.** El stack interno anda; lo que falla es la identidad TLS del origen. El log de `cloudflared` dice cuál de las tres causas es — **fijate en qué nombre esperaba**, ahí está la diferencia entre la primera y la tercera:

```bash
docker compose logs --tail=20 cloudflared | grep -o 'error="[^"]*"' | sort -u
```

- **`x509: certificate is valid for <hash>.<hash>.traefik.default, not traefik`** → el **Origin Server Name está vacío** en el Public Hostname del Tunnel. `cloudflared` valida el cert contra el nombre del servicio (`traefik`); Traefik no tiene router para ese SNI y devuelve su self-signed por defecto. Se arregla **solo en el dashboard** (Zero Trust → Networks → Tunnels → el Tunnel → Public Hostname → Additional application settings → TLS → Origin Server Name = `$PUBLIC_HOSTNAME`). `cloudflared` recarga solo, sin restart: confirmalo con `docker compose logs --tail=5 cloudflared | grep "Updated to new configuration"`, que debe mostrar `"originServerName":"<tu PUBLIC_HOSTNAME>"`.
- **`x509: certificate signed by unknown authority`**, o `make verify-odoo` reporta un certificado `(STAGING)` → hay un `caServer` de staging activo en `config/traefik/traefik.yaml`. La CA de staging de Let's Encrypt no es confiable para `cloudflared`. Sacar la línea `caServer` (el default de Traefik ya es producción), borrar el cert cacheado y recrear:

  ```bash
  rm -f config/traefik/acme.json && install -m 600 /dev/null config/traefik/acme.json
  docker compose up -d --force-recreate traefik
  ```

  Tarda ~60s en emitir. **Borrar `acme.json` es obligatorio**: sin eso Traefik sigue sirviendo el cert de staging cacheado, que todavía es válido.

- **`x509: certificate is valid for <hash>.<hash>.traefik.default, not <tu PUBLIC_HOSTNAME>`** — el hostname real, **no** `traefik` → el Origin Server Name está bien; lo que falta es el certificado. Traefik nunca lo emitió y sigue sirviendo su self-signed. La causa está en su log:

  ```bash
  docker compose logs traefik | grep -iE "acme|unable" | tail -5
  ```

  `failed to find zone <tu-dominio>.: [status code 403] 9109: Invalid access token` → el token de `secrets/cloudflare_api_token` no sirve. Cuál de las dos variantes es, sin exponerlo en `ps` (`printf` es builtin):

  ```bash
  printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/user/tokens/verify"\n' "$(sudo cat secrets/cloudflare_api_token)" | curl -s --config -
  ```

  - `code 1000 "Invalid API Token"` → el valor está mal pegado. Confirmalo con `sudo wc -c < secrets/cloudflare_api_token`: son **40 bytes sin salto de línea**. Cualquier otro número es un token truncado, con basura alrededor, o directamente otra credencial.
  - `"status":"active"` (y el `9109` solo contra `/zones`) → el token vive pero no puede leer la zona. Le falta `Zone:Read`: rehacelo con la plantilla **Edit zone DNS**.

  En ambos casos, con el token nuevo cargado:

  ```bash
  sudo make secrets-perms && make secrets-check
  docker compose up -d --force-recreate traefik
  ```

  El `--force-recreate` no es opcional — ver "Un secret rotado no surte efecto" más abajo. **No borres `acme.json`**: a diferencia del caso de staging, acá no hay cert cacheado que estorbe, el registro de cuenta ACME sigue siendo válido, y el fallo fue contra la API de Cloudflare sin llegar a Let's Encrypt (no se quemó rate limit de validaciones fallidas).

Para aislar en qué eslabón está el problema, un contenedor descartable en la red `edge` (`cloudflared` es distroless, no tiene shell propia):

```bash
docker run --rm --network infrastructure-odoo_edge curlimages/curl -sk -o /dev/null -w "%{http_code}\n" https://traefik:443 -H "Host: $PUBLIC_HOSTNAME"
```

Si eso da `303`/`200`, Traefik y Odoo están bien y el problema es exclusivamente TLS entre `cloudflared` y Traefik — o sea, una de las dos causas de arriba.

**Ruido en los logs de `cloudflared`.** Pedidos a `/actuator/env`, `/info.php`, `/config.json`, `/.env`, rutas de Jira/WordPress. Son bots escaneando el hostname público, aparecen desde que el DNS queda expuesto. No es un compromiso; no hace falta actuar. Al contar errores conviene acotar la ventana (`--since 5m`) para no mezclarlos con fallas viejas ya resueltas.

**El certificado no se renueva, o se reemite todo el tiempo.** Traefik renueva solo a los 30 días de vencer, **siempre que `config/traefik/acme.json` persista**. Tiene que ser un **archivo** de modo `600`, no un directorio — Docker lo crea como directorio cuando falta al primer `up`, y entonces Traefik nunca persiste el cert y lo reemite hasta chocar con el rate-limit de Let's Encrypt. Lo chequea `make verify-host`; el fix está en el mensaje de `scripts/config-init.sh`.

El resolver **no declara `email`** y es deliberado: ACME lo define opcional y Let's Encrypt dejó de mandar avisos de vencimiento el 2025-06-04. La vigilancia del certificado es activa en su lugar — la alerta `cert-por-vencer` dispara a los 21 días restantes, o sea ~9 después de que la renovación automática debió correr, y cubre también un `acme.json` vaciado o convertido en directorio, porque sin serie la regla alerta igual.

## Capa de datos

**`postgres`/`pgbouncer` `unhealthy`.** Causas típicas: permisos incorrectos en `pgbouncer_credentials` (si estás probando en Mac en vez del servidor real, ver la nota previa sobre macOS), el archivo no tiene el formato exacto `"odoo" "password"` (comillas incluidas), o el puerto ya está ocupado por otra instancia de Postgres en el host.

## Odoo core

**El entrypoint falla al arrancar.** Causas típicas: GID incorrecto en `odoo_admin_password`/`zeptomail_smtp_password` — deben ser `101`, y se arregla con `sudo make secrets-perms && make secrets-check` (el mapa vive en `scripts/secrets-perms.sh`, no en el runbook); Postgres/PgBouncer todavía no están `healthy` cuando Odoo intenta conectar (confirmar que `make verify-db` pasa antes de arrancar Odoo); o el `addons_path` quedó **vacío** y el entrypoint aborta a propósito (`addons_path vacío — ¿corriste make addons-sync...?`), que Desde el paso a bind-mount, es la causa más frecuente: los addons llegan por bind-mount desde `addons/production/`, así que su presencia ya no la garantiza la imagen — se arregla con `make addons-sync`, y si eso falla por credencial, el PAT vive en `~/.git-credentials` del host (ver `docs/addons.md`).

## Backups y DR

**`unable to restore while PostgreSQL is running` con Postgres ya detenido.** Quedó un `postmaster.pid` de un apagado sucio. La imagen usa `STOPSIGNAL SIGINT` (fast shutdown), pero con Odoo y PgBouncer conectados no alcanza a cerrar en los 10s por defecto y Docker lo mata. Se resuelve parando con timeout: `docker compose stop -t 60 postgres`. Confirmar que el pid file no está antes de reintentar.

**El WAL se acumula en `pg_wal` (archivos `.ready` que crecen).** El archivado está roto y el disco de la base se va a llenar. Causas típicas: credencial de R2 vencida o mal rotada, `PGBACKREST_STANZA` vacío en `.env`, o el bucket inalcanzable. Diagnóstico: `docker compose exec -u postgres postgres pgbackrest check`. Los backups full/diff pueden seguir aparentando éxito mientras esto pasa — por eso `check` corre primero en cada corrida diaria.

**Un secret rotado no surte efecto, o el contenedor reporta `No such file`.** Los secrets son bind-mounts de **archivo**, atados al inode. Editarlos con algo que reemplace el archivo (`sed -i`, varios editores) desvincula el inode montado. El contenedor queda viendo el archivo viejo o ninguno, y **restaurar el contenido no lo arregla**. Solución: `docker compose up -d --force-recreate <servicio>`. Verificar además el GID con `make secrets-check`: si la herramienta recreó el archivo, probablemente también perdió el grupo.

**`unable to find primary cluster` en `stanza-create`.** pgBackRest se conecta a la base como rol `postgres`, que en este cluster no existe (se creó con `POSTGRES_USER=odoo`). La stanza tiene que declarar `pg1-user = odoo`; ya viene así en `config/pgbackrest/pgbackrest.conf`.

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
