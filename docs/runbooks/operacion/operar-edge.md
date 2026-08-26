# Operar edge

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar `dnsmasq` + `nginx` + `cloudflared` sin tocar el resto del stack — por ejemplo, para aplicar un cambio en la config de nginx, o para diagnosticar el borde sin arriesgar la capa de datos.

`certbot` pertenece a esta capa pero **no es un servicio de larga vida**: está bajo `profiles: [cert]` y corre como one-off. No se opera con estos comandos sino con `make cert-issue` / `make cert-renew` (y el timer de systemd que lo dispara solo).

## Objetivo

La capa de borde en el estado pedido, sin afectar datos ni aplicación — que siguen sirviendo (o caídos) independientemente de lo que le pase a esta capa, salvo que `down` deje a Odoo sin forma de recibir tráfico externo.

## Comandos

```bash
make nginx-up        # levanta los servicios de esta capa presentes en este stack
make nginx-down       # los baja
make edge-restart    # docker compose restart — reinicia los contenedores existentes, no recrea
make edge-logs
make edge-ps
make nginx-verify
```

Qué servicios de borde trae *este* stack lo dice su entrypoint: producción lleva `nginx`+`cloudflared`+`certbot` y, si el cliente tiene servidor local, `dnsmasq` con `COMPOSE_PROFILES=lan`; prueba lleva los tres primeros sin publicar puertos; y development solo `nginx` sin TLS, sin túnel ni certbot.

`edge-restart` **no** reemite el certificado ni aplica un cambio de imagen o de compose — para eso hace falta `edge-down` + `edge-up`. Si el cambio es solo en la config montada de nginx (`stacks/nginx/`), alcanza con recargar en caliente en vez de reiniciar el contenedor entero:

```bash
docker compose exec nginx nginx -s reload
```

**Bajar esta capa deja el hostname público sin responder** hasta que vuelva a subir — `cloudflared` es el único camino de entrada, no hay puerto publicado directo a Odoo.

## Verificación

```bash
make nginx-verify
```

Cubre los servicios `healthy`, que `server-tls.conf` no tenga el placeholder de `server-tls.conf.example` sin reemplazar, el `server_name`, el `proxy_pass` por variable con el resolver de Docker, los días de vigencia del certificado, las conexiones del Tunnel y el token de Cloudflare contra la API. En un stack sin TLS (development) omite certificado y 443, y avisa en vez de fallar donde corresponda.

---

**Destructivo — `make edge-nuke`.** Borra containers, imágenes **y el volumen `letsencrypt`**, donde vive el certificado emitido. Pide tipear la palabra `nuke`, no un Y/N.

Consecuencia a tener presente: sin ese volumen, **nginx no vuelve a arrancar** hasta reemitir con `make cert-issue` ([levantar-produccion](../entorno/levantar-produccion.md), bloque 3 · Edge). Y Let's Encrypt limita cuántos certificados se emiten por dominio en una ventana de tiempo — no es un comando para repetir a la ligera.
