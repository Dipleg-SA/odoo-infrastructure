# Operar observability

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar `prometheus` + `loki` + `grafana` + `alloy` sin tocar el resto del stack. Exclusiva de producción — staging y development no la llevan.

## Objetivo

La capa de observabilidad en el estado pedido. Bajarla no afecta a Odoo ni a los datos: es diagnóstico, no una dependencia de la aplicación.

## Comandos

No hay target agrupado — la limpieza de `docker/` lo sacó junto con `capa.sh`: cada
stack se opera solo, sin dispatcher. `up`/`down` encadenan los cuatro; `logs`/`ps`
van directo por `docker compose` con los cuatro nombres, para verlos juntos en una
sola llamada — encadenar `make X-logs` no sirve porque el primer `-f` bloquea.

```bash
make prometheus-up && make loki-up && make grafana-up && make alloy-up
make prometheus-down && make loki-down && make grafana-down && make alloy-down
docker compose restart prometheus loki grafana alloy   # no recrea contenedores
docker compose logs -f prometheus loki grafana alloy
docker compose ps prometheus loki grafana alloy
make prometheus-verify
```

`loki` es el único de los cuatro servicios sin `(healthy)` en `docker compose ps`, y es correcto: su imagen es distroless estricta, sin binario con el cual ejecutar un healthcheck. Su caída la cubre `up == 0` en Prometheus, que lo scrapea directo — por eso la topología es híbrida: Prometheus scrapea por pull todo lo que ya expone HTTP (`cloudflared`, Loki, Grafana, sí mismo y el propio Alloy), y Alloy solo empuja lo que ningún pull alcanza. Si todo se empujara por el agente, la muerte de Alloy no dispararía ninguna alerta.

Grafana se abre por túnel SSH, no publica puerto directo: `ssh -N -L 3001:127.0.0.1:3001 <usuario>@<ip-de-administración>`, corrido **desde tu máquina**, nunca desde el servidor.

## Verificación

```bash
make prometheus-verify
```

Cubre los cuatro servicios, que ningún target de Prometheus esté caído, las tres familias de métricas que empuja Alloy (host, contenedores, base), que Loki reciba logs por contenedor, los binds, y que la rotación de logs del daemon (`host/daemon.json`) haya quedado aplicada al contenedor de Odoo.

---

**Destructivo — sin target, a mano.** Por la misma limpieza de arriba tampoco queda un
nuke acotado a esta capa: el único que sobrevive es `make nuke`, **global**, que además
de estos tres volúmenes se lleva `pgdata` — la base de producción. No es sustituto de
esto: para borrar solo el histórico de observabilidad,

```bash
docker compose rm -sf prometheus loki grafana alloy
docker volume rm "${COMPOSE_PROJECT_NAME}_prometheus-data" \
  "${COMPOSE_PROJECT_NAME}_loki-data" "${COMPOSE_PROJECT_NAME}_grafana-data"
```

Los cinco dashboards y las siete reglas de alerta están provisionados como archivos en `stacks/grafana/config/provisioning/`, así que esto no los pierde — se recrean solos al volver a subir con `make grafana-up`. Lo que sí se pierde, y no se recupera, es el histórico de métricas y logs: no entra en ningún backup, es diagnóstico, no datos de negocio.
