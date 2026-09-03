# Crear el Tunnel de Cloudflare

## Cuándo se usa

Antes de clonar el repositorio — el Tunnel es la única vía de entrada del stack, no hay puerto publicado directo a Odoo. Necesitás la [zona de Cloudflare](crear-zona-cloudflare.md) ya creada y tu `PUBLIC_HOSTNAME` decidido (el subdominio + dominio con el que vas a servir la instancia).

## Objetivo

Un Tunnel creado y con su ruta pública configurada —apuntando a `nginx:443` con el hostname correcto en el certificado— y su token guardado, listo para que `cloudflared` se conecte apenas levante.

## A mano

1. **Crear el Tunnel:** Zero Trust → Networks → Tunnels → crear uno nuevo, tipo *Cloudflared*. Te da el token del conector.
2. **Public Hostname**, en el mismo Tunnel → pestaña Public Hostname:

| Campo | Valor |
|---|---|
| Subdomain + Domain | Los que componen tu `PUBLIC_HOSTNAME` |
| Service | `https://nginx:443` — nginx y cloudflared comparten la red `edge` del stack, se resuelven por nombre de contenedor |
| TLS → **Origin Server Name** | Tu `PUBLIC_HOSTNAME` completo — el campo que se olvida |
| TLS → No TLS Verify | desactivado |

**El campo Origin Server Name vacío no se ve vacío.** El dashboard le pone de placeholder la palabra `Null` en gris, que a simple vista se confunde con un valor ya cargado. Si no lo ves escrito en texto negro, no está seteado.

Sin Origin Server Name, `cloudflared` cae al hostname del propio Service (`nginx`) para validar el certificado, que no es a quién se lo emitió Let's Encrypt, y el sitio entero da **502** — recién visible cuando Odoo ya sirve tráfico real (ver [levantar-produccion](levantar-produccion.md)). El error, en `docker compose logs cloudflared`, es inconfundible:

```
tls: failed to verify certificate: x509: certificate is valid for <tu PUBLIC_HOSTNAME>, not nginx
```

## Verificación

Todavía no hay `cloudflared` corriendo — el token recién se prueba de verdad cuando el repositorio esté clonado y la capa `edge` levantada. Guardalo: va a `secrets/cloudflare_tunnel_token`.

Lo único chequeable ahora es el campo que más se olvida:

- [ ] Origin Server Name tiene tu `PUBLIC_HOSTNAME` completo, en texto negro (no el placeholder `Null`)
- [ ] Service es `https://nginx:443`, no `http` ni otro puerto

---

Para rotarlo más adelante: [rotar-token-cloudflare-tunnel](../credenciales/rotar-token-cloudflare-tunnel.md).
