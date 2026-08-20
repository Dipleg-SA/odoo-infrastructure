# Operar observability

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar `prometheus` + `loki` + `grafana` + `alloy` sin tocar el resto del stack. Exclusiva de producción — staging y development no la llevan.

## Objetivo

La capa de observabilidad en el estado pedido. Bajarla no afecta a Odoo ni a los datos: es diagnóstico, no una dependencia de la aplicación.

## Comandos

```bash
make observability-up
make observability-down
make observability-restart   # docker compose restart — no recrea contenedores
make observability-logs
make observability-ps
make observability-verify
```

`loki` es el único de los cuatro servicios sin `(healthy)` en `docker compose ps`, y es correcto: su imagen es distroless estricta, sin binario con el cual ejecutar un healthcheck. Su caída la cubre `up == 0` en Prometheus, que lo scrapea directo — por eso la topología es híbrida: Prometheus scrapea por pull todo lo que ya expone HTTP (`cloudflared`, Loki, Grafana, sí mismo y el propio Alloy), y Alloy solo empuja lo que ningún pull alcanza. Si todo se empujara por el agente, la muerte de Alloy no dispararía ninguna alerta.

Grafana se abre por túnel SSH, no publica puerto directo: `ssh -N -L 3001:127.0.0.1:3001 <usuario>@<ip-de-administración>`, corrido **desde tu máquina**, nunca desde el servidor.

## Verificación

```bash
make observability-verify
```

Cubre los cuatro servicios, que ningún target de Prometheus esté caído, las tres familias de métricas que empuja Alloy (host, contenedores, base), que Loki reciba logs por contenedor, los binds, y que la rotación de logs del daemon (`config/docker/daemon.json`) haya quedado aplicada al contenedor de Odoo.

---

**Destructivo — `make observability-nuke`.** Borra containers, imágenes **y los tres volúmenes** de la capa (`prometheus-data`, `loki-data`, `grafana-data`). Pide tipear `nuke`.

Los cinco dashboards y las siete reglas de alerta están provisionados como archivos en `config/grafana/provisioning/`, así que el nuke no los pierde — se recrean solos al volver a subir. Lo que sí se pierde, y no se recupera, es el histórico de métricas y logs: no entra en ningún backup, es diagnóstico, no datos de negocio.
