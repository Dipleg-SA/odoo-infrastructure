# Configurar el webhook de GitHub

## Cuándo se usa

Al publicar el receptor del checkout canónico o rotar su secreto de firma.

## Objetivo

Entregar pushes de ramas de integración al endpoint sin ampliar los permisos del receptor.

## A mano

Generá un secreto aleatorio y guardalo en el archivo privado de firma del runtime de control. Configurá GitHub con evento `push`, tipo de contenido JSON y la URL exacta `https://<hostname>/webhooks/addons`.

## Comandos

```bash
ENTORNO=produccion make secrets-init
$EDITOR runtime/control/secrets/addons_webhook_secret
sudo ENTORNO=produccion make secrets-perms
ENTORNO=produccion make addons-webhook-verify
```

El mismo bootstrap deja los archivos `git_readonly_token`, `git_readonly_key` y
`git_known_hosts` bajo `runtime/control/secrets/`; cargá allí las credenciales de
lectura del catálogo antes de ejecutar `secrets-check`.

El receptor valida `X-Hub-Signature-256`, repositorio, rama y línea mayor antes de usar Git. El repositorio Enterprise no se registra como catálogo ni como webhook.

## Verificación

Enviá una entrega de prueba desde GitHub y comprobá que la rama de integración actualiza solo su candidato. Una firma inválida, una rama `feat/*` o un repositorio no catalogado no debe modificar candidatos ni imágenes.
