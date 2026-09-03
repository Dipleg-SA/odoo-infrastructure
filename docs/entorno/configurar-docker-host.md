# Configurar Docker en el host

## Cuándo se usa

Antes de clonar el repositorio en un servidor nuevo — el stack entero corre sobre Docker Compose y ninguno de sus scripts instala el motor.

## Objetivo

Docker Engine y Compose ≥ 2.20 instalados, el daemon arrancando solo tras un reinicio, y claro qué protege — y qué no — el firewall del host una vez que Docker está corriendo.

## A mano

Instalación: seguí la documentación oficial de Docker para tu distribución — este repositorio no la reproduce, cambia por sistema operativo y versión. Confirmá que el plugin Compose (`docker compose`, no el standalone `docker-compose`) quedó instalado: lo trae el paquete `docker-compose-plugin` en las distros basadas en Debian/Ubuntu.

`envs/production.yaml` usa la directiva `include:`, que exige Compose ≥ 2.20 — versiones más viejas fallan al resolver la composición, no al arrancar un contenedor.

## Comandos

```bash
echo "# 1 → Arranque automático del daemon"
sudo systemctl enable docker
```

Sin esto el stack no vuelve solo después de un reinicio del servidor — `docker compose up` no se relanza por su cuenta.

## Verificación

```bash
echo "# 2 → Versión y arranque automático"
docker compose version --short
systemctl is-enabled docker
```

El primero tiene que dar `2.20` o superior; el segundo, `enabled`. `make host-verify` (una vez clonado el repositorio, ver [levantar-produccion](levantar-produccion.md)) vuelve a chequear los dos junto con el resto de la config.

---

**El firewall del host no protege a los contenedores.** Docker publica puertos por DNAT e inserta sus reglas antes de las cadenas del firewall: un `deny` de `ufw`/`iptables` no alcanza a un puerto publicado por un contenedor — el filtro llega tarde. El aislamiento real de cada servicio es la IP a la que se publica (`ports:` en el `compose.yaml` de cada stack), nunca el firewall, y eso ya está resuelto en los compose de este repositorio. La única regla de firewall que sigue haciendo falta es la de [configurar-dhcp-dns-lan](configurar-dhcp-dns-lan.md) para el `53/udp` de `dnsmasq`, que corre en `network_mode: host` y por eso sí pasa por `INPUT`.
