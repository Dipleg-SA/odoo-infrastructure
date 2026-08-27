#!/usr/bin/env bash
# Orquestador de la verificación del árbol nuevo (stacks/ + envs/).
#
# NO sabe qué se espera de ningún stack: eso vive en stacks/<nombre>/verify.sh,
# que es su dueño único. Acá solo se decide QUÉ stacks hay que correr, y eso sale
# de la composición resuelta, nunca de una lista mantenida a mano.

. "$(dirname "${BASH_SOURCE[0]}")/lib/verify.sh"

# --- Qué stacks corren ---
# La intersección entre los que tienen verify.sh y los que la composición declara.
# Un stack que este entorno no lleva no es un fallo: se omite nombrándolo.

correr_stack() {
  local nombre="$1" archivo="stacks/$1/verify.sh"

  if [ ! -f "$archivo" ]; then
    omitir "stack $nombre" "no tiene verify.sh todavía"
    return
  fi
  if ! declarado "$nombre"; then
    omitir "stack $nombre" "no está en este stack"
    return
  fi

  # Sourceado, no ejecutado: así comparte los contadores y el resumen es uno solo.
  # shellcheck disable=SC1090
  . "$archivo"
  "v_$nombre"
}

# --- Descubrimiento ---
# Del directorio, no de una lista: agregar un stack con su verify.sh alcanza para
# que entre acá. Ordenado para que la salida sea estable entre corridas.

stacks_con_verify() {
  local d
  for d in stacks/*/verify.sh; do
    [ -f "$d" ] || continue
    d=${d#stacks/}; printf '%s\n' "${d%/verify.sh}"
  done | sort
}

# --- Entrada ---
# 'all' corre host y todos los stacks; un nombre corre solo ese, para que
# make <stack>-verify no tenga que reimplementar nada.

case "${1:-all}" in
  all)
    . scripts/verify-host.sh
    v_host
    # for y no `while read`: los chequeos corren `docker compose exec -T`, que se
    # come el stdin del bucle y deja stacks sin verificar en silencio. Se midió:
    # con nginx arriba, odoo y postgres no llegaban a correr.
    for s in $(stacks_con_verify); do
      correr_stack "$s"
    done
    ;;
  host)
    . scripts/verify-host.sh
    v_host
    ;;
  *)
    if [ ! -f "stacks/$1/verify.sh" ]; then
      ui_bad "no hay stack '$1' en este árbol" \
        "con COMPOSE_FILE en envs/, los stacks son: $(stacks_con_verify | tr '\n' ' ')" >&2
      exit 2
    fi
    correr_stack "$1"
    ;;
esac

resumen
