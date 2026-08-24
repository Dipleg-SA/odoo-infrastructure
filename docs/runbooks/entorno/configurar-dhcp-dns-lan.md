# Configurar el DHCP de la LAN para usar dnsmasq

## Cuándo se usa

Después de levantar la capa `edge` en producción ([levantar-produccion](levantar-produccion.md), bloque 3 · Edge) — `dnsmasq` queda sano y resolviendo el hostname público a la IP local, pero nadie de la LAN lo consulta hasta que el router se lo indique por DHCP. Exclusivo de producción: `dnsmasq` corre solo ahí (`network_mode: host` sobre el `53`, sin segunda instancia posible — ver [compose.dns.yaml](../../../docker/compose.dns.yaml)).

## Objetivo

Los dispositivos de la LAN reciben la IP del servidor como DNS primario, resuelven el hostname público directo a la IP local sin salir a internet y volver por NAT, y conservan un DNS público como secundario — así una caída del servidor no deja a la LAN entera sin resolución de nombres.

## Prerrequisito del servidor

`ufw allow 53/udp` desde la subred LAN, si el host lo usa. `dnsmasq` corre en `network_mode: host`, así que entra por la cadena `INPUT` y no lo cubre el DNAT de Docker: sin esta regla, el router puede apuntar perfecto a `${LOCAL_IP}` y las consultas igual se pierden.

```bash
sudo ufw allow from <subred-lan>/24 to any port 53 proto udp
make host-verify   # "ufw permite 53/udp desde la LAN" tiene que dar ok
```

## A mano

Configuración en el router/DHCP de la red, fuera de este repositorio — el mecanismo exacto varía por fabricante, el concepto es el mismo en cualquiera:

1. **Reservar la IP del servidor.** El campo DNS del DHCP guarda una IP fija; si el servidor la recibe dinámicamente, el día que cambie el router sigue apuntando a una IP vieja y la LAN pierde resolución en silencio. Reservar la MAC del servidor a `${LOCAL_IP}` — la sección suele llamarse "reserva de direcciones" o "DHCP reservation".
2. **DNS primario → `${LOCAL_IP}`.** La misma IP que `dnsmasq` bindea (`--listen-address` en [compose.dns.yaml](../../../docker/compose.dns.yaml)).
3. **DNS secundario → un resolver público**, el mismo que uses en `DNS_FORWARDER_1`/`DNS_FORWARDER_2` del `.env` u otro cualquiera. No es cosmético: si la capa `edge` se cae (mantenimiento, `make edge-down`, `edge-nuke`), la LAN necesita a dónde caer.
4. **Aplicar y renovar.** Un cambio de DHCP no empuja a los clientes ya conectados — o esperan a que expire su lease, o hace falta forzar la renovación (reconectar Wi-Fi, `ipconfig /renew`, reiniciar el dispositivo).

Poner acá un DNS local **no evita que se caiga internet** — solo evita que el hostname propio dependa de que el WAN esté arriba. Cualquier dominio externo sigue resolviendo vía `DNS_FORWARDER_1`/`2`, que necesitan salida real a internet.

## Verificación

Desde un dispositivo de la LAN — nunca desde el propio servidor, un self-query puede dar timeout por NAT sin que sea un problema real:

```bash
echo "# 1 → El dispositivo recibió al servidor como DNS primario"
# Windows: ipconfig /all | grep -i "servidores dns"
# macOS/Linux: cat /etc/resolv.conf, o networksetup -getdnsservers <servicio>
```

```bash
echo "# 2 → El hostname público resuelve a la IP local, no a la de Cloudflare"
HOST_PUB='el-hostname-publico'
dig +short "$HOST_PUB"
```

Si el 2 devuelve `${LOCAL_IP}`, el router ya usa `dnsmasq`. Si devuelve una IP de Cloudflare, el router sigue con el DNS anterior — repasá el paso 2 de "A mano" y confirmá con el paso 1 que el dispositivo de prueba efectivamente renovó su lease.

```bash
echo "# 3 → Un dominio externo sigue resolviendo — prueba el forwarder, no solo el hostname propio"
dig +short example.com
```

Si el 3 falla, es `dnsmasq` sin forwarders alcanzables (`DNS_FORWARDER_1`/`2` del `.env`), no un problema del router.

Para confirmar que el DNS secundario sostiene la LAN si el servidor se cae, apagá `dnsmasq` un momento y repetí el paso 3 — tiene que seguir resolviendo, esta vez por el secundario:

```bash
echo "# 4 → Simular la caída del servidor — desde el servidor"
docker compose stop dnsmasq
```

```bash
echo "# 5 → Desde la LAN, repetir el paso 3 — tiene que resolver igual"
dig +short example.com
docker compose start dnsmasq   # revertir el paso 4
```

Si el 5 falla, no hay DNS secundario configurado en el router, o apunta a un resolver inalcanzable — ver "A mano", paso 3. Para diagnosticar por qué `dnsmasq` no responde, ver [dnsmasq no bindea o no resuelve](../troubleshooting/edge/dnsmasq-no-bindea-o-no-resuelve.md).
