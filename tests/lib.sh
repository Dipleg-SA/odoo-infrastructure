#!/usr/bin/env bash
# Arnés de los tests. Mismo vocabulario que verify.sh —ok, FALLA, un renglón por
# chequeo— para que las dos salidas se lean igual. Sin dependencias.

# Sin -e, por el mismo motivo que verify.sh: un corredor que aborta en la primera
# falla esconde el resto, que es justo para lo que se lo corre.
set -uo pipefail

PASS=0; FALLO=0

ok()     { printf '  ok      %s\n' "$1"; PASS=$((PASS+1)); }
bad()    { printf '  FALLA   %s\n            %s\n' "$1" "$2"; FALLO=$((FALLO+1)); }
titulo() { printf '\n%s\n' "$1"; }

# --- Aserciones ---
# Igualdad, subcadena presente y subcadena ausente. El nombre describe la conducta
# esperada, no la mecánica: es lo que se lee cuando falla.

igual() {
  local nombre="$1" esperado="$2" actual="$3"
  if [ "$esperado" = "$actual" ]; then ok "$nombre"
  else bad "$nombre" "esperaba '$esperado', obtuve '$actual'"; fi
}

contiene() {
  local nombre="$1" patron="$2" texto="$3"
  case "$texto" in
    *"$patron"*) ok "$nombre" ;;
    *) bad "$nombre" "no aparece '$patron' en: $(printf '%s' "$texto" | head -2 | tr '\n' ' ')" ;;
  esac
}

no_contiene() {
  local nombre="$1" patron="$2" texto="$3"
  case "$texto" in
    *"$patron"*) bad "$nombre" "aparece '$patron' y no debería" ;;
    *) ok "$nombre" ;;
  esac
}

# --- Código de salida ---
# Se pasa el esperado y el comando; captura la salida para no ensuciar el reporte.

sale_con() {
  local nombre="$1" esperado="$2"; shift 2
  local salida codigo
  salida=$("$@" 2>&1); codigo=$?
  if [ "$codigo" -eq "$esperado" ]; then ok "$nombre"
  else bad "$nombre" "esperaba exit $esperado, obtuve $codigo: $(printf '%s' "$salida" | head -1)"; fi
}

# --- Resumen ---
# El exit code es lo que consume el Makefile y el CI.

resumen() {
  printf '\n%s ok · %s fallas\n' "$PASS" "$FALLO"
  [ "$FALLO" -eq 0 ]
}
