# Crear la zona de Cloudflare y su token de API

## Cuándo se usa

Antes de clonar el repositorio — es el primer prerrequisito de toda la instalación. La delegación del DNS puede tardar hasta 48h en propagar, y de ella depende también la verificación del dominio de envío de [ZeptoMail](configurar-zeptomail.md): es el camino crítico del resto de los prerrequisitos.

## Objetivo

Tu dominio administrado por Cloudflare, con el DNS delegado desde el registrador, y un token de API acotado a esa zona con permiso para escribir registros DNS — el que usa `certbot` para la emisión del certificado por DNS-01.

## A mano

1. **Zona:** en Cloudflare, agregá tu dominio. Te da los nameservers a apuntar.
2. **Delegación:** en el registrador (donde compraste el dominio), reemplazá sus nameservers por los que dio Cloudflare.
3. **Token de API:** Cloudflare → Perfil → API Tokens → plantilla **Edit zone DNS**, acotado a esta zona. Con `Zone:DNS:Edit` a secas la emisión falla con `403 9109` — necesita también `Zone:Read`.

## Comandos

```bash
echo "# 1 → Completá tu zona"
ZONA='ejemplo.com'
```

```bash
echo "# 2 → La zona está delegada a Cloudflare"
dig +short NS "$ZONA"
```

Tiene que devolver nameservers de Cloudflare — no los del registrador original. Si tarda en propagar, repetir más tarde; no hay forma de acelerarlo.

```bash
echo "# 3 → Token de zona DNS (pegalo y Enter, no se muestra)"
read -rs CF_TOKEN && CF_RESP=$(printf 'header = "Authorization: Bearer %s"\nurl = "https://api.cloudflare.com/client/v4/zones?name=%s"\n' "$CF_TOKEN" "$ZONA" \
  | curl -s --config -) \
  && echo "$CF_RESP" \
  && echo "$CF_RESP" | grep -q "\"name\":\"$ZONA\"" && echo "OK: token válido para $ZONA"
```

## Verificación

El bloque 3 de arriba ya es la verificación: imprime el JSON crudo y, si matchea tu zona, un `OK` final. Sin `OK`: `1000` en el JSON = token mal copiado · `9109` = le falta `Zone:Read` · `"result":[]` = el token apunta a otra zona.

Guardá el token — va a `secrets/cloudflare_api_token` cuando clones el repositorio (ver [levantar-produccion](levantar-produccion.md)).

---

Para rotarlo más adelante, no crear uno nuevo: [rotar-token-cloudflare-api](../credenciales/rotar-token-cloudflare-api.md).
