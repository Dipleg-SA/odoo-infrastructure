# Crear el bucket de R2 y su token

## Cuándo se usa

Antes de clonar el repositorio — es la credencial más sensible del stack: abre el repositorio de backups.

## Objetivo

Un bucket R2 nuevo y vacío, un token `Object Read & Write` acotado a él, y la passphrase de cifrado de restic generada y guardada — nada de esto se puede recuperar después si se pierde.

## A mano

1. Cloudflare → R2 → crear un bucket nuevo y vacío.
2. Token de API de R2, permiso `Object Read & Write`, acotado a ese bucket únicamente.
3. Anotar el endpoint (sin esquema, ej. `<account-id>.r2.cloudflarestorage.com`) y el nombre del bucket — no van a `.env`: van a `stacks/backup/config/r2.env`, real por checkout, bootstrapeado desde su `.example` en [levantar-produccion](levantar-produccion.md).

## Comandos

La passphrase de cifrado de restic se inventa acá, no en R2.

```bash
echo "# → Passphrase de restic, a secrets/restic_password"
openssl rand -hex 32
```

Hex y no base64: los `/ + =` rompen a cualquier consumidor que arme una URI con la credencial adentro.

> **Al gestor de contraseñas ahora, antes de seguir.** Perderla deja el repositorio de backups irrecuperable — no hay procedimiento. Y no la dejes solo en el servidor: si el servidor es lo que se perdió, ahí no la vas a poder buscar. Mismo trato para el token de R2, que puede vaciar el bucket (R2 no tiene versioning). Una vez guardada, cerrá la terminal: a diferencia de los tokens, esta sí queda impresa en el scrollback.

## Verificación

No hay forma de probar la clave de R2 todavía — se prueba por primera vez con `make backup-run` (ver [levantar-produccion](levantar-produccion.md)). Lo único a confirmar ahora:

- [ ] El bucket está vacío y es nuevo — no reusado de otro deployment
- [ ] El token es `Object Read & Write`, acotado a este bucket, no a la cuenta entera
- [ ] La passphrase y el token de R2 ya están en el gestor de contraseñas, fuera del servidor

---

Para rotar la clave de acceso más adelante: [rotar-credenciales-r2](../credenciales/rotar-credenciales-r2.md).
