# Rotar token de Cloudflare (API)

## Cuándo se usa

El token de `secrets/cloudflare_api_token` venció, se filtró, o toca rotarlo por política. Es el que usa certbot para la validación DNS-01 — sin él, ni la emisión inicial ni la renovación del certificado funcionan.

## Objetivo

Token nuevo funcionando en la próxima emisión/renovación, el viejo revocado en Cloudflare.

## Flujo rápido

Conservá el token anterior hasta validar la autenticación del nuevo.

1. **Crear un token nuevo** con permisos DNS de edición y lectura para la zona; ver
   [A mano](#a-mano).
2. **Reemplazar el secret y corregir permisos**; ver [Comandos](#comandos).
3. **Probar el desafío DNS en modo dry-run.** Revocar el token anterior solo después de confirmar
   que no hay errores de autenticación; ver [Verificación](#verificación).

## A mano

Crear el token nuevo en Cloudflare: plantilla **Edit zone DNS**, acotado a tu zona. Con `Zone:DNS:Edit` a secas la emisión falla con `403 9109` — necesita también `Zone:Read`.

## Comandos

```bash
echo "# 1 → Reemplazar el archivo — sin comillas, sin salto de línea final"
sudo -e secrets/cloudflare_api_token
```

Cloudflare emite dos formatos según cuándo lo creaste: 40 caracteres el viejo, `cfut_...` (~46) el nuevo — los dos son válidos.

```bash
echo "# 2 → Verificar contra la API antes de confiar en el archivo"
ZONA='ejemplo.com'   # tu zona en Cloudflare — no PUBLIC_HOSTNAME si servís por un subdominio
CF_TOKEN=$(sudo cat secrets/cloudflare_api_token)
CF_RESP=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones?name=%s"\n' "$CF_TOKEN" "$ZONA" \
  | curl -s --config -)
echo "$CF_RESP" | grep -q "\"name\":\"$ZONA\"" && echo "OK: token válido"
```

```bash
echo "# 3 → Permisos, por si el reemplazo del archivo perdió el grupo"
sudo make secrets-perms
```

**No hace falta reiniciar ningún contenedor**: certbot corre como one-off, así que cada invocación monta el secret actualizado. `make cert-renew` solo renueva certificados que ya están próximos a vencer; para probar ahora el token sin emitir ni guardar un certificado real, usá el modo de prueba contra Let's Encrypt:

```bash
echo "# 4 → Probar la renovación y el desafío DNS sin cambiar el certificado instalado"
docker compose run --rm certbot renew --dry-run --force-renewal
```

## Verificación

El comando anterior tiene que terminar con la renovación de prueba exitosa y sin errores de autenticación. `certbot certificates` solo muestra certificados locales, así que no valida el token contra Cloudflare. Recién con la prueba DNS-01 confirmada, **revocar el token viejo** en el dashboard de Cloudflare.
