#!/usr/bin/env bash
# El orquestador: qué stacks corre y cuáles omite. No prueba QUÉ espera cada
# stack —eso es de su propio verify.sh— sino el descubrimiento y la agregación,
# que es lo único que la Etapa 2 introduce de nuevo.
#
# Corre el orquestador como proceso, no sourceado: lo que se afirma es su salida
# y su exit code, que es lo que consume el operador.

cd "$(dirname "$0")/.."
. tests/lib.sh

STUB_DIR=$(mktemp -d); export STUB_DIR
trap 'rm -rf "$STUB_DIR"' EXIT

# --- Arnés ---
# Los stubs interceptan docker; COMPOSE_FILE en envs/ es lo que hace que el ruteo
# de verify.sh entregue el trabajo al orquestador.

orquestador() {
  PATH="$PWD/tests/stubs:$PATH" COMPOSE_FILE="envs/development.yaml" \
    scripts/verify-stacks.sh "$@" 2>&1
}

servicios_fixture() { printf '%s\n' "$1" > "$STUB_DIR/servicios"; }

# =====================================================================
titulo "descubrimiento — qué stacks corre"
# =====================================================================

# Los tres stacks de la Etapa 1 declarados: los tres tienen que aparecer.
servicios_fixture $'nginx\nodoo\npostgres'
SALIDA=$(orquestador all)

contiene "corre el stack nginx"    "nginx"    "$SALIDA"
contiene "corre el stack odoo"     "odoo"     "$SALIDA"
contiene "corre el stack postgres" "postgres" "$SALIDA"

# El host va primero: sus prerrequisitos explican los fallos de los stacks.
contiene "los chequeos de host van primero" "host" "$SALIDA"

# =====================================================================
titulo "un stack ausente se omite, no se marca en rojo"
# =====================================================================

# Composición sin odoo: que este entorno no lo lleve es una decisión, no un fallo.
servicios_fixture $'nginx\npostgres'
SALIDA=$(orquestador all)

contiene "nombra que no está en este stack" "no está en este stack" "$SALIDA"

# La distinción que hace creíble la salida: ausente ≠ caído. Un stack ausente no
# puede aportar fallas, así que su sección entera no se corre.
no_contiene "y no corre sus chequeos" "odoo sirve en :8069" "$SALIDA"

# =====================================================================
titulo "agregación — un solo resumen para todos los stacks"
# =====================================================================

servicios_fixture $'nginx\nodoo\npostgres'
SALIDA=$(orquestador all)

igual "un único resumen al cierre" "1" "$(printf '%s\n' "$SALIDA" | grep -c 'ok · .* fallas')"

# Contar líneas de resumen NO alcanza: sin la guarda de doble sourceo sigue
# saliendo una sola, con los contadores del último stack nada más. Lo que lo
# detecta es el total contra los renglones realmente impresos — se midió: sin
# guarda el resumen decía 2 fallas sobre 12 impresas.

# El propio renglón del resumen empieza con ✗ cuando hubo fallas: sin excluirlo
# se cuenta a sí mismo y el total nunca cierra.
SIN_RESUMEN=$(printf '%s\n' "$SALIDA" | grep -v 'ok · .* fallas')

FALLAS_IMPRESAS=$(printf '%s\n' "$SIN_RESUMEN" | grep -c '^✗ ')
FALLAS_RESUMEN=$(printf '%s\n' "$SALIDA" | sed -n 's/.*ok · \([0-9]*\) fallas.*/\1/p')
igual "el resumen suma las fallas de TODOS los stacks" "$FALLAS_IMPRESAS" "$FALLAS_RESUMEN"

OK_IMPRESOS=$(printf '%s\n' "$SIN_RESUMEN" | grep -c '^✓ ')
OK_RESUMEN=$(printf '%s\n' "$SALIDA" | sed -n 's/.*[✓✗] \([0-9]*\) ok ·.*/\1/p')
igual "y también los ok" "$OK_IMPRESOS" "$OK_RESUMEN"

# =====================================================================
titulo "exit code — lo que consume el operador"
# =====================================================================

# El stub no levanta nada, así que los stacks declarados fallan por no estar
# corriendo: el orquestador tiene que propagarlo, no tragárselo.
servicios_fixture $'nginx\nodoo\npostgres'
orquestador all >/dev/null 2>&1
igual "con fallas sale distinto de 0" "1" "$?"

# =====================================================================
titulo "un stack suelto — make <stack>-verify"
# =====================================================================

servicios_fixture $'nginx\nodoo\npostgres'
SALIDA=$(orquestador postgres)

contiene    "corre el que se le pide"   "postgres" "$SALIDA"
no_contiene "y ninguno de los otros"    "resolver de Docker declarado" "$SALIDA"

# Una capa del árbol viejo no existe acá: decirlo es mejor que verificar nada y
# dar verde. El mensaje nombra los stacks reales para que el operador corrija.
SALIDA=$(orquestador db)
igual    "una capa vieja sale con error"  "2" "$(orquestador db >/dev/null 2>&1; echo $?)"
contiene "y nombra los stacks que sí hay" "nginx odoo postgres" "$SALIDA"

resumen
