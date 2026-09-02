# Entornos: qué comparten y qué colisiona

Un **entorno** acá es una combinación de tres cosas: un checkout del repositorio, un
nombre de proyecto de Compose, y el entrypoint de `envs/` que elige qué stacks entran.
Cambiar cualquiera de las tres da un entorno distinto.

Qué es un stack y qué declara cada quién está en
[modular-architecture.md](modular-architecture.md) y no se repite acá. Este documento
responde otra cosa: **qué pasa cuando dos entornos conviven en el mismo servidor**, que
es el caso real de producción y prueba.

## Los tres entornos

|                    | Producción                | Prueba                  | Development             |
|--------------------|---------------------------|-------------------------|-------------------------|
| Dónde corre        | Servidor                  | Servidor                | Máquina del operador    |
| Checkout           | propio                    | propio                  | uno por feature         |
| Nombre de proyecto | `production`              | `staging`               | `development-<feature>` |
| Entrypoint         | `envs/production.yaml`    | `envs/staging.yaml`     | `envs/development.yaml` |
| Rama de addons     | default del Dockerfile    | `<versión>-stag`        | `feat/*`                |
| Proxy              | nginx con TLS, en la LAN  | nginx con TLS, en loopback  | nginx sin TLS, loopback |
| Túnel y certbot    | sí                        | sí                      | no                      |
| DNS local          | solo con servidor local   | no                      | no                      |
| Respalda           | sí                        | **no**, solo restaura   | no                      |
| Observabilidad     | sí                        | no                      | no                      |
| Secrets            | 9                         | 7                       | 2, los dos generados    |

**Que prueba no respalde es estructural, no una omisión.** Su entrypoint le pone
`profiles: [restore]` al stack `backup`, así que queda fuera de la composición por
defecto — y `timers.sh`, que deriva las units de ahí, no instala los timers de backup.
Sin eso, un `sudo make up-timers` en prueba dejaría una corrida nocturna
escribiendo en el repositorio de producción y apagando su alerta de backup viejo.
`compose run` alcanza igual al servicio con el perfil inactivo, así que restaurar
funciona sin activar nada.

---

## Cuatro niveles de compartición

No todo se comparte del mismo modo. El nivel decide si dos entornos conviven o se pisan.

### 1. Archivos versionados — compartidos por definición

Todo lo que está en git es el mismo archivo para todo checkout que salga de ese commit.
Cambiarlo para uno lo cambia para todos. Los `compose.yaml`, los entrypoints, los
scripts y el `Makefile` entran acá: el operador no los toca.

### 2. Config real por checkout — no compartido, y por eso divergen

Cada `.example` se bootstrapea con `cp` a un archivo real gitignoreado. Dos checkouts
en el mismo servidor tienen su propio `stacks/nginx/config/server-tls.conf`, su propio
`postgresql.conf` y su propio `.env`. **Ahí es donde los entornos difieren de verdad**,
y por eso ninguno de esos valores está parametrizado en el compose.

El caso peligroso es copiar el `.env` de un checkout a otro: se lleva
`COMPOSE_PROJECT_NAME`, y con él los volúmenes. Contra eso no hay mecanismo — solo la
advertencia en cada plantilla.

### 3. Recursos de Docker con alcance de proyecto — no compartidos

Contenedores, volúmenes, redes y tags de imagen derivan de `COMPOSE_PROJECT_NAME`. Dos
entornos con nombres distintos no se ven entre sí, ni siquiera para los datos.

El nombre de una imagen **sí es global al daemon**: por eso cada stack declara
`image: local/<nombre>:${COMPOSE_PROJECT_NAME}`. Con un tag fijo, el `build` de un
entorno pisaría la imagen que corre el otro, sin avisar.

### 4. Recursos globales al host — compartidos siempre

Acá está lo que colisiona:

| Recurso | Quién lo toma | Qué pasa con un segundo entorno |
|---|---|---|
| `:80` y `:443` de la LAN | nginx de producción | prueba publica en `127.0.0.1:8080`/`:8443`, y development en `:8081` |
| `:53` en `network_mode: host` | dnsmasq | no admite un segundo de ninguna forma — por eso prueba **no lo incluye**, y no alcanza con no activarle el perfil |
| `:3001` de la UI de Grafana | grafana de producción | prueba no lleva observabilidad |
| units de systemd | las de cada checkout | van prefijadas con el nombre del proyecto, así que no se pisan |
| `/etc/docker/daemon.json` | el daemon | uno solo para todo el host; lo instala `make host-init` |
| repositorio de restic en R2 | producción escribe | prueba **lee**: mismo repositorio, credencial de solo lectura |

---

## Lo que la observabilidad de producción ve

Alloy monta el socket de Docker y `/rootfs`, así que **mide el host entero**: sus
métricas de contenedores incluyen los de prueba, y sus logs también. Es deliberado —
un contenedor que se reinicia en loop importa venga del entorno que venga.

Lo que no cruza es la base: el exporter de Postgres apunta a `postgres` por nombre
dentro de la red `app` de su propio proyecto, así que solo ve la suya.

---

## Pendientes

**El resolver de la LAN no lo decide este repositorio.** `dnsmasq` resuelve el hostname
para quien le pregunte, pero quién le pregunta lo reparte el DHCP del router. Es un
prerrequisito escrito en
[configurar-dhcp-dns-lan.md](entorno/configurar-dhcp-dns-lan.md), un `dig` sin
`@` desde un equipo de la LAN, y un `omitir` explícito en el verify de dnsmasq que dice
que desde el servidor no se puede verificar. **Sigue sin haber mecanismo**, porque no lo
hay del lado del stack — lo que hay es que dejó de dar verde por accidente.

**El workflow de CI sigue sin poder existir.** Hay una suite de `make test` más `bash -n`
listos para correr en cada push, y ningún lugar donde correrlos: es una decisión
pendiente sobre dónde vive el repositorio, no trabajo técnico pendiente.
