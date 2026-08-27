#!/usr/bin/env bash
# Qué se espera del stack loki. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.
#
# Sin `sano`: la imagen es distroless estricta y no tiene healthcheck posible. El
# caso "vivo pero no sirve" lo cubre que Prometheus lo scrapee, y que de verdad
# reciba logs — que es lo único que prueba la cadena entera.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_loki() {
  titulo "loki"

  if ! declarado loki; then
    omitir "loki levantado" "no está en este stack"
    return
  fi
  if ! corriendo loki; then
    bad "loki levantado" "no está corriendo"
    omitir "Loki recibe logs por contenedor" "loki no está corriendo"
    omitir "loki:3100 sin publicar" "loki no está corriendo"
    return
  fi
  ok "loki up (sin healthcheck propio: imagen distroless)"

  # --- Logs de verdad, etiquetados por contenedor ---
  # La consulta sale desde prometheus y no desde el host: loki no publica puerto,
  # así que preguntarle desde afuera daría un falso rojo.

  # El request sale de prometheus, así que su estado también condiciona: sin la
  # guarda, un prometheus caído se reporta como si Loki no recibiera logs.
  if ! corriendo prometheus; then
    omitir "Loki recibe logs por contenedor" "$(motivo prometheus)"
  else
    expect "Loki recibe logs por contenedor" "odoo" docker compose exec -T prometheus \
      wget -qO- 'http://loki:3100/loki/api/v1/label/container/values'
  fi

  # --- Binds ---

  sin_publicar loki 3100
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_loki
resumen
