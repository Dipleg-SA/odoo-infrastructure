# Rotar token del Tunnel (Cloudflare)

## Cuándo se usa

El token de `secrets/cloudflare_tunnel_token` venció, se filtró, o toca rotarlo por política. Es el que usa `cloudflared`, un contenedor **de larga vida** — a diferencia del token de API, este sí necesita recrear el contenedor para tomar el valor nuevo.

## Objetivo

`cloudflared` reconectado con el token nuevo, el viejo revocado.

## Flujo rápido

Generá el token nuevo y completá la prueba de conexión antes de cerrar la rotación.

1. **Generar un token nuevo para el Tunnel**; ver [A mano](#a-mano).
2. **Actualizar el secret y recrear `cloudflared`** para que cargue el nuevo valor; ver
   [Comandos](#comandos).
3. **Confirmar conexión y acceso público**; después revocar o eliminar el token anterior si
   sigue activo; ver [Verificación](#verificación).

## A mano

En Zero Trust → Networks → Tunnels → el Tunnel, generar (o rotar) el token del conector.

## Comandos

```bash
echo "# 1 → Reemplazar el archivo"
sudo -e secrets/cloudflare_tunnel_token
sudo make secrets-perms
```

**Recrear el contenedor, no reiniciarlo.** Los secrets son bind-mounts de archivo, atados al inode: un `restart` no relee el contenido si el editor reemplazó el archivo en vez de modificarlo in-place, y `cloudflared` de por sí solo lee el token al arrancar.

```bash
echo "# 2 → Force-recreate para que levante con el token nuevo"
docker compose up -d --force-recreate cloudflared
```

## Verificación

```bash
docker compose logs -f cloudflared
```

Buscar la conexión establecida (`Registered tunnel connection`) sin errores de autenticación. Probar el sitio público de punta a punta:

```bash
curl -sI "https://$PUBLIC_HOSTNAME/web/login" | grep -iE "^HTTP|^server:|^cf-ray:"
```

Tienen que salir los tres headers — solo Cloudflare los agrega. Recién con esto confirmado, **revocar/eliminar el token viejo** en el dashboard.
