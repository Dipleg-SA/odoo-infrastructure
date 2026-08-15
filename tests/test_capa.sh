#!/usr/bin/env bash
# capa.sh: qué servicios resuelve por capa contra la composición real, que una
# capa ausente se omite sin fallar, y que nuke nunca corre sin la palabra exacta.

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"
. tests/lib.sh

TMP=$(mktemp -d)
STUB_DIR="$TMP/stub"; mkdir -p "$STUB_DIR"; export STUB_DIR
trap 'rm -rf "$TMP"' EXIT
PATH="$REPO_ROOT/tests/stubs:$PATH"

ROOT="$TMP/root"
mkdir -p "$ROOT/scripts/lib"
cp "$REPO_ROOT/scripts/capa.sh" "$ROOT/scripts/"
cp "$REPO_ROOT/scripts/lib/ui.sh" "$ROOT/scripts/lib/"

# El bloque volumes: real que nuke tiene que leer para saber qué volumen es dueño de db.
cat > "$ROOT/compose.db.yaml" <<'EOF'
volumes:
  pgdata:

services:
  postgres:
    image: postgres
  pgbouncer:
    image: pgbouncer
EOF

llamadas() { cat "$STUB_DIR/llamadas" 2>/dev/null; }
reset_stub() { : > "$STUB_DIR/llamadas"; rm -f "$STUB_DIR/servicios" "$STUB_DIR/salida"; }
capa() { (cd "$ROOT" && ./scripts/capa.sh "$@" 2>&1); }
capa_code() { (cd "$ROOT" && ./scripts/capa.sh "$@" >/dev/null 2>&1); echo $?; }

# =====================================================================
titulo "capa ausente del stack: se omite, no falla"
# =====================================================================

reset_stub
printf 'nginx\nodoo\n' > "$STUB_DIR/servicios"   # ni postgres ni pgbouncer declarados
SALIDA=$(capa db up)
igual       "sale con 0" "0" "$(capa_code db up)"
contiene    "dice que la capa no está" "la capa db no está en este stack" "$SALIDA"
no_contiene "no llama a compose up" "compose up" "$(llamadas)"

# =====================================================================
titulo "capa presente: up/restart pasan justo sus servicios, nunca de más"
# =====================================================================

reset_stub
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
capa db up >/dev/null 2>&1
contiene "up lleva postgres y pgbouncer, no odoo" "compose up -d postgres pgbouncer" "$(llamadas)"

reset_stub
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
capa db restart >/dev/null 2>&1
contiene "restart usa el subcomando nativo de compose" "compose restart postgres pgbouncer" "$(llamadas)"

# =====================================================================
titulo "host no tiene ciclo de vida de contenedores"
# =====================================================================

reset_stub
SALIDA=$(capa host up)
igual    "host up sale con 2" "2" "$(capa_code host up)"
contiene "dirige a host-verify" "usá 'make host-verify'" "$SALIDA"
igual    "no llega a tocar docker" "" "$(llamadas)"

# =====================================================================
titulo "nuke: sin la palabra exacta, no toca nada"
# =====================================================================

reset_stub
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
SALIDA=$(printf 'si\n' | capa db nuke)
igual       "cancelado sale con 1" "1" "$(printf 'si\n' | capa_code db nuke)"
contiene    "avisa que se canceló" "cancelado" "$SALIDA"
no_contiene "nunca llama a compose rm" "compose rm" "$(llamadas)"
no_contiene "nunca llama a volume rm"  "volume rm" "$(llamadas)"

# =====================================================================
titulo "nuke: con 'nuke' de verdad, borra containers y el volumen dueño"
# =====================================================================

reset_stub
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
SALIDA=$(printf 'nuke\n' | capa db nuke)
contiene "borra los containers de la capa" "compose rm -sf postgres pgbouncer" "$(llamadas)"
contiene "borra el volumen dueño de db (pgdata)" "volume rm -f pgdata" "$(llamadas)"
contiene "cierra con éxito"                      "db-nuke listo" "$SALIDA"

resumen
