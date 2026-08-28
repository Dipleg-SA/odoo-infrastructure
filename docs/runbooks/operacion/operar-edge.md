# Operar edge

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar `dnsmasq` + `nginx` + `cloudflared` sin tocar el resto del stack — por ejemplo, para aplicar un cambio en la config de nginx, o para diagnosticar el borde sin arriesgar la capa de datos.

`certbot` pertenece a esta capa pero **no es un servicio de larga vida**: está bajo `profiles: [cert]` y corre como one-off. No se opera con estos comandos sino con `make cert-issue` / `make cert-renew` (y el timer de systemd que lo dispara solo).

## Objetivo

La capa de borde en el estado pedido, sin afectar datos ni aplicación — que siguen sirviendo (o caídos) independientemente de lo que le pase a esta capa, salvo que `down` deje a Odoo sin forma de recibir tráfico externo.

## Comandos

No hay target agrupado — la limpieza de `docker/` lo sacó junto con `capa.sh`: cada
stack se opera solo, sin dispatcher. Sumá `&& make dnsmasq-up` (o `-down`/`-restart`)
solo si este stack lo lleva (`COMPOSE_PROFILES=lan` en producción) — medido: nombrarlo
explícito en `up`/`restart` salta el filtro de `profiles:` aunque el perfil esté
inactivo, así que en producción sin LAN **no** falla con "no such service" como
parecería razonable esperar — intenta arrancar igual, y si `dnsmasq.conf` nunca se
bootstrapeó, queda reintentando en loop, inofensivo pero molesto (ver
[levantar-produccion](../entorno/levantar-produccion.md), bloque 3 · Edge). El "no
such service" real aparece si el stack directamente no incluye `dnsmasq` en su
composición, como staging o development.

```bash
make nginx-up && make cloudflared-up
make nginx-down && make cloudflared-down
make nginx-restart && make cloudflared-restart   # no recrea contenedores
docker compose logs -f nginx cloudflared dnsmasq
docker compose ps nginx cloudflared dnsmasq
make nginx-verify
```

Qué servicios de borde trae *este* stack lo dice su entrypoint: producción lleva `nginx`+`cloudflared`+`certbot` y, si el cliente tiene servidor local, `dnsmasq` con `COMPOSE_PROFILES=lan`; prueba lleva los tres primeros sin publicar puertos; y development solo `nginx` sin TLS, sin túnel ni certbot.

**Un `restart` no reemite el certificado ni aplica un cambio de imagen o de compose** — para eso hace falta bajar y volver a subir cada servicio (`make nginx-down && make cloudflared-down`, después `make nginx-up && make cloudflared-up`). Si el cambio es solo en la config montada de nginx (`stacks/nginx/`), alcanza con recargar en caliente en vez de reiniciar el contenedor entero:

```bash
docker compose exec nginx nginx -s reload
```

**Bajar esta capa deja el hostname público sin responder** hasta que vuelva a subir — `cloudflared` es el único camino de entrada, no hay puerto publicado directo a Odoo.

## Verificación

```bash
make nginx-verify
make certbot-verify
make cloudflared-verify
```

Tres comandos porque cada stack es dueño de lo suyo. `nginx-verify` cubre el servicio `healthy`, que `server-tls.conf` no tenga el placeholder de `server-tls.conf.example` sin reemplazar, el `server_name`, el `proxy_pass` por variable con el resolver de Docker, las tres rutas de Odoo, que la cadena nginx → Odoo responda de verdad, el log sin errores y los binds. `certbot-verify` cubre los días de vigencia del certificado, el timer de renovación y el token de la API de Cloudflare contra la API real. `cloudflared-verify` cubre las conexiones del Tunnel. En un stack sin TLS (development) `nginx-verify` omite certificado, `server_name` y 443, y avisa en vez de fallar donde corresponda; `certbot-verify` y `cloudflared-verify` no aplican ahí.

---

**Destructivo — sin target, a mano.** Tampoco sobrevivió un nuke acotado a esta capa:
el único que queda es `make nuke`, **global** — se lleva `pgdata`, la base de
producción, junto con todo lo demás. No es sustituto de esto. Para borrar solo el
certificado (`rm -sf` no rompe con un servicio que este stack no lleva, a diferencia
de `restart`/`up`):

```bash
docker compose rm -sf nginx certbot cloudflared dnsmasq
docker volume rm "${COMPOSE_PROJECT_NAME}_letsencrypt"
```

Consecuencia a tener presente: sin ese volumen, **nginx no vuelve a arrancar** hasta reemitir con `make cert-issue` ([levantar-produccion](../entorno/levantar-produccion.md), bloque 3 · Edge). Y Let's Encrypt limita cuántos certificados se emiten por dominio en una ventana de tiempo — no es un comando para repetir a la ligera.
