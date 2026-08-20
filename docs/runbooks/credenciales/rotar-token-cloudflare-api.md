# Rotar token de Cloudflare (API)

## Cuándo se usa

El token de `secrets/cloudflare_api_token` venció, se filtró, o toca rotarlo por política. Es el que usa certbot para la validación DNS-01 — sin él, ni la emisión inicial ni la renovación del certificado funcionan.

## Objetivo

Token nuevo funcionando en la próxima emisión/renovación, el viejo revocado en Cloudflare.

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
CF_TOKEN=$(sudo cat secrets/cloudflare_api_token)
CF_RESP=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones?name=%s"\n' "$CF_TOKEN" "$PUBLIC_HOSTNAME" \
  | curl -s --config -)
echo "$CF_RESP" | grep -q "\"name\":" && echo "OK: token válido"
```

```bash
echo "# 3 → Permisos, por si el reemplazo del archivo perdió el grupo"
sudo make secrets-perms
```

**No hace falta reiniciar ningún contenedor**: certbot corre como one-off (`docker compose --profile cert run --rm certbot`) en cada emisión o renovación, así que el archivo nuevo se usa desde la próxima corrida sin recrear nada.

```bash
echo "# 4 → Probar de verdad con una renovación forzada"
make cert-renew
```

## Verificación

```bash
docker compose --profile cert run --rm certbot certificates
```

Sin errores de autenticación. Recién con esto confirmado, **revocar el token viejo** en el dashboard de Cloudflare.
