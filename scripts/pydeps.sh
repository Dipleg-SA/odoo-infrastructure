#!/usr/bin/env bash
# --- Dependencias Python de los addons ---
# check: ¿requirements.txt cubre lo que declaran los manifiestos? Puro host, sin red.
# sync: resuelve versión contra la imagen base y pinea lo que falte — nunca reescribe un pin ya puesto.

set -euo pipefail
shopt -s nullglob

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh

REQUIREMENTS="docker/odoo/requirements.txt"

# --- Manifiestos ---
# Una fila por __manifest__.py bajo cada categoría; el layout lo fija entrypoint.sh.

manifest_files() {
  local category
  for category in enterprise custom-addons oca third-party; do
    find "addons/$category" -name __manifest__.py 2>/dev/null || true
  done
}

# --- external_dependencies.python ---
# ast.literal_eval, no exec: un manifiesto es un dict literal, nunca hace falta correrlo.

declared_deps() {
  [ "$#" -eq 0 ] && return 0
  python3 - "$@" <<'PY'
import ast, sys

names = set()
for path in sys.argv[1:]:
    try:
        with open(path) as f:
            manifest = ast.literal_eval(f.read())
    except (SyntaxError, ValueError):
        continue
    names.update(manifest.get("external_dependencies", {}).get("python", []))

for n in sorted(names):
    print(n)
PY
}

# --- Normalización de nombre (PEP 503, simplificada) ---
# 'Pillow' y 'pillow', o 'python-dateutil' y 'python_dateutil', se tratan igual.

norm() { tr 'A-Z_.' 'a-z--'; }

declared_names() {
  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(manifest_files)
  [ "${#files[@]}" -eq 0 ] && return 0
  declared_deps "${files[@]}" | norm | sort -u
}

pinned_names() {
  [ -f "$REQUIREMENTS" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$REQUIREMENTS" | sed -E 's/^([A-Za-z0-9._-]+).*/\1/' | norm | sort -u
}

missing_names() { comm -23 <(declared_names) <(pinned_names); }
orphan_names()  { comm -13 <(declared_names) <(pinned_names); }

# --- check: sin red, sin Docker — corre en 'make test' ---

cmd_check() {
  local missing orphans
  missing=$(missing_names)
  if [ -n "$missing" ]; then
    ui_bad "pydeps check: faltan en $REQUIREMENTS" "$(tr '\n' ' ' <<<"$missing")"
    return 1
  fi
  ui_ok "pydeps check: $REQUIREMENTS cubre lo que declaran los addons"
  orphans=$(orphan_names)
  [ -n "$orphans" ] && ui_warn "pineados de más, ningún addon los declara" "$(tr '\n' ' ' <<<"$orphans")"
  return 0
}

# --- sync: resuelve contra la imagen base y pinea lo que falte ---
# --no-deps a propósito: pinea solo lo que un addon declara. Las transitivas las
# resuelve pip en build time como siempre — un lockfile completo (con transitivas
# congeladas) pediría pip-tools o poetry, dependencia nueva por una precisión
# que hoy nadie pidió.

cmd_sync() {
  local missing image reporte orphans resueltos pedidos resueltos_n

  missing=$(missing_names)
  if [ -z "$missing" ]; then
    ui_ok "pydeps sync: nada nuevo que pinear"
  else
    image=$(sed -n 's/^FROM \(.*\)$/\1/p' docker/odoo/Dockerfile | head -1)
    pedidos=$(wc -l <<<"$missing" | tr -d ' ')
    ui_start "pydeps sync: resolviendo $pedidos paquete(s) contra $image"

    # --ignore-installed: sin esto, un paquete que ya viene del sistema operativo de
    # la imagen base (ej. vía apt) queda "already satisfied" y el reporte lo omite —
    # se pinea igual, porque un bump de la imagen base puede dejar de traerlo.

    if ! reporte=$(docker run --rm "$image" \
        pip install --break-system-packages --dry-run --quiet --no-deps --ignore-installed \
          --report - $missing 2>&1); then
      ui_bad "pydeps sync: no se pudo resolver contra $image" "$(tail -1 <<<"$reporte")"
      return 1
    fi

    resueltos=$(echo "$reporte" | python3 -c '
import json, sys

data = json.load(sys.stdin)
for item in data["install"]:
    m = item["metadata"]
    print(m["name"] + "==" + m["version"])
' | sort)

    [ -n "$resueltos" ] && echo "$resueltos" >> "$REQUIREMENTS"
    resueltos_n=$([ -n "$resueltos" ] && wc -l <<<"$resueltos" | tr -d ' ' || echo 0)

    ui_ok "pydeps sync: $resueltos_n paquete(s) agregados a $REQUIREMENTS"
    if [ "$resueltos_n" -lt "$pedidos" ]; then
      ui_warn "pip no resolvió todo lo pedido" "revisar nombres en: $(tr '\n' ' ' <<<"$missing")"
    fi
  fi

  orphans=$(orphan_names)
  [ -n "$orphans" ] && ui_warn "pineados de más, ningún addon los declara" "$(tr '\n' ' ' <<<"$orphans")"
  return 0
}

# --- Sourceado desde los tests ---
# Sin esto, importar los helpers correría el comando entero y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

case "${1:-}" in
  check) cmd_check ;;
  sync)  cmd_sync ;;
  *) echo "uso: $(basename "$0") check|sync" >&2; exit 2 ;;
esac
