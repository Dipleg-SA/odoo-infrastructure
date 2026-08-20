# dnsmasq no bindea o no resuelve

## Síntoma

`dnsmasq` no arranca, o arranca pero no responde consultas DNS desde la LAN.

## Diagnóstico

```bash
sudo ss -ulnp | grep ':53'
```

Tiene que mostrar `dnsmasq` escuchando en `${LOCAL_IP}:53`. Corre en `network_mode: host` (no publica puerto vía Docker), escuchando directo ahí (`--listen-address` + `--bind-interfaces`).

Dos causas, ambas surgidas en el primer deploy real:

- **systemd-resolved (Ubuntu):** un bind wildcard `0.0.0.0:53` choca con su stub listener en `127.0.0.53:53` (`failed to bind host port ...:53/udp: address already in use`).
- **`ufw`:** un publish de Docker a una IP específica (UDP) no llega al contenedor a través del NAT/FORWARD con `ufw` en `deny (routed)`. Como proceso del host, el tráfico de `dnsmasq` entra por INPUT, donde la regla de `ufw` sí lo permite.

El test real es **desde un dispositivo de la LAN**, no desde el propio servidor:

```bash
dig <PUBLIC_HOSTNAME> @<LOCAL_IP>
```

El servidor consultándose a sí mismo puede dar timeout por NAT sin que sea un problema real.

## Fix

Al escuchar solo en `${LOCAL_IP}` (no wildcard) se evita el choque con systemd-resolved. Para el firewall:

```bash
sudo ufw allow from <subred-lan>/24 to any port 53 proto udp
```

Es un prerrequisito del servidor (ver [levantar-produccion](../../entorno/levantar-produccion.md)), no algo que este stack pueda resolver solo.
