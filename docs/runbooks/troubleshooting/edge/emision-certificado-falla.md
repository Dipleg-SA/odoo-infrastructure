# La emisión del certificado falla

## Síntoma

`make cert-issue` o `make cert-renew` fallan.

## Diagnóstico

El log de certbot nombra la causa:

```bash
docker compose --profile cert run --rm certbot certificates
```

Cuál credencial es, sin exponerla en `ps` (`printf` es builtin):

```bash
printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/user/tokens/verify"\n' "$(sudo cat secrets/cloudflare_api_token)" | curl -s --config -
```

## Fix

- `[status code 403] 9109` o similar contra la API de Cloudflare → el token de `secrets/cloudflare_api_token` no sirve.
- `code 1000 "Invalid API Token"` → el valor está mal pegado. Confirmá con `sudo wc -c < secrets/cloudflare_api_token`: son **40 bytes sin salto de línea** (o ~46 para el formato `cfut_...`). Cualquier otro número es un token truncado, con basura alrededor, o directamente otra credencial.
- `"status":"active"` (y el `9109` solo contra `/zones`) → el token vive pero no puede leer la zona. Le falta `Zone:Read`: rehacelo con la plantilla **Edit zone DNS**. Ver [rotar-token-cloudflare-api](../../credenciales/rotar-token-cloudflare-api.md).
- Si falla por **validación** y no por credencial, subí el `--dns-cloudflare-propagation-seconds` de `scripts/cert.sh` (`cmd_issue`): certbot está pidiendo la verificación antes de que el registro TXT haya propagado.
