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

# Una segunda capa con compose real, para probar que 'all ps' agrupa más de una
# y saltea las que no tienen compose.*.yaml en este fixture (edge/backups/observability).
cat > "$ROOT/compose.odoo.yaml" <<'EOF'
volumes:
  odoo-data:

services:
  odoo:
    image: odoo
EOF

llamadas() { cat "$STUB_DIR/llamadas" 2>/dev/null; }
reset_stub() {
  : > "$STUB_DIR/llamadas"
  rm -f "$STUB_DIR/servicios" "$STUB_DIR/salida" "$STUB_DIR/config" \
        "$STUB_DIR/imagenes" "$STUB_DIR/rmi" "$STUB_DIR/exit-rmi"
}

# --- Composición resuelta ---
# Lo que 'docker compose config' devuelve de verdad: el volumen declarado 'pgdata'
# ya viene con su nombre real, prefijado por el nombre del proyecto.
composicion_resuelta() {
  cat > "$STUB_DIR/config" <<'EOF'
name: testproj
services:
  postgres:
    image: postgres
volumes:
  pgdata:
    name: testproj_pgdata
  odoo-data:
    name: testproj_odoo-data
EOF
}
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
composicion_resuelta
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
SALIDA=$(printf 'si\n' | capa db nuke)
igual       "cancelado sale con 1" "1" "$(printf 'si\n' | capa_code db nuke)"
contiene    "avisa que se canceló" "cancelado" "$SALIDA"
no_contiene "nunca llama a compose rm" "compose rm" "$(llamadas)"
no_contiene "nunca llama a volume rm"  "volume rm" "$(llamadas)"

# =====================================================================
titulo "nuke: borra el volumen por su nombre REAL, no por el declarado"
# =====================================================================
# 'docker volume rm -f' sobre un nombre inexistente sale con 0 y sin mensaje: borrar
# por el nombre declarado dejaría los datos en disco y reportaría éxito igual.

reset_stub
composicion_resuelta
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
SALIDA=$(printf 'nuke\n' | capa db nuke)
contiene    "borra los containers de la capa" "compose rm -sf postgres pgbouncer" "$(llamadas)"
contiene    "borra el volumen con el nombre que Docker conoce" "volume rm -f testproj_pgdata" "$(llamadas)"
no_contiene "nunca por el nombre declarado, que en Docker no existe" "volume rm -f pgdata" "$(llamadas)"
contiene    "y nombra el real antes de pedir confirmación" "volúmenes (testproj_pgdata)" "$SALIDA"
no_contiene "no toca el volumen de otra capa" "odoo-data" "$(llamadas)"
contiene    "cierra con éxito" "db-nuke listo" "$SALIDA"

# =====================================================================
titulo "nuke: una imagen en uso por otra capa avisa, no vuelve fallido al nuke"
# =====================================================================
# restore-db comparte la imagen de postgres, y restore-files la de backup: con el otro
# arriba, el rmi falla. Lo irrecuperable —containers y volúmenes— ya se borró, y la
# imagen se rehace con un build, así que el exit code no puede decir que falló todo.

reset_stub
composicion_resuelta
printf 'postgres\npgbouncer\n' > "$STUB_DIR/servicios"
printf 'sha256:abc123\n' > "$STUB_DIR/imagenes"
printf 'Error response from daemon: conflict: unable to delete abc123 (cannot be forced) - image is being used by running container def456\n' > "$STUB_DIR/rmi"
echo 1 > "$STUB_DIR/exit-rmi"

SALIDA=$(printf 'nuke\n' | capa db nuke)
igual    "sale con 0: lo destructivo se completó" "0" "$(printf 'nuke\n' | capa_code db nuke)"
contiene "borró el volumen igual"       "volume rm -f testproj_pgdata" "$(llamadas)"
contiene "avisa que la imagen quedó"    "alguna imagen quedó sin borrar" "$SALIDA"
contiene "y arrastra el motivo de docker" "image is being used by running container" "$SALIDA"
contiene "cierra como listo, no como falla" "db-nuke listo" "$SALIDA"

# =====================================================================
titulo "nuke: si no se puede resolver el nombre real, falla — no borra a medias"
# =====================================================================
# Sin composición legible, el nombre real es desconocido: borrar los containers y
# fallar en silencio con los volúmenes es justo el resultado que hay que evitar.

reset_stub
printf 'postgres\npgbouncer\n' > "$STUB_DIR/servicios"   # sin fixture de config
SALIDA=$(printf 'nuke\n' | capa db nuke)
igual       "sale con 1" "1" "$(printf 'nuke\n' | capa_code db nuke)"
contiene    "dice que no pudo resolverlos" "no se pudo resolver el nombre real" "$SALIDA"
no_contiene "y no borró ningún container"  "compose rm" "$(llamadas)"

# =====================================================================
titulo "ps: la capa puntual usa la tabla compacta con sus propios servicios"
# =====================================================================

reset_stub
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
capa db ps >/dev/null 2>&1
contiene "pasa los servicios de la capa y el formato compacto" \
  "compose ps postgres pgbouncer --format table" "$(llamadas)"

# =====================================================================
titulo "ps agrupado: un título por capa presente, salteando las que faltan"
# =====================================================================

reset_stub
printf 'postgres\npgbouncer\nodoo\n' > "$STUB_DIR/servicios"
SALIDA=$(capa all ps)
contiene    "muestra el título de db"                          "$(printf '\ndb\n')" "$SALIDA"
contiene    "muestra el título de odoo"                        "$(printf '\nodoo\n')" "$SALIDA"
no_contiene "saltea edge (sin compose.*.yaml en este fixture)" "$(printf '\nedge\n')" "$SALIDA"

# =====================================================================
titulo "ps agrupado: el servicio sin capa se lista igual, y la composición se resuelve una vez"
# =====================================================================

reset_stub
printf 'postgres\npgbouncer\nrestore-db\n' > "$STUB_DIR/servicios"
SALIDA=$(capa all ps)
contiene "agrupa la capa db"                        "$(printf '\ndb\n')"    "$SALIDA"
contiene "abre un grupo 'otros'"                    "$(printf '\notros\n')" "$SALIDA"
contiene "lista restore-db con sus profiles"        "--profile restore ps restore-db" "$(llamadas)"
igual    "consulta la composición una sola vez" "1" "$(llamadas | grep -c 'config --services')"

# =====================================================================
titulo "ps agrupado: si docker no responde, falla — no un éxito vacío"
# =====================================================================

reset_stub
echo 1 > "$STUB_DIR/exit"
SALIDA=$(capa all ps); CODIGO=$(capa_code all ps)
rm -f "$STUB_DIR/exit"
igual    "no se hace pasar por éxito" "1" "$CODIGO"
contiene "y dice que falló"           "ps falló" "$SALIDA"

resumen
