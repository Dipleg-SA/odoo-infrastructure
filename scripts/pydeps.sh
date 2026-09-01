#!/usr/bin/env bash
# --- Dependencias Python de los addons ---
# check: ¿requirements.txt cubre lo que declaran los manifiestos? Puro host, sin red.
# sync: resuelve versión contra la imagen base y pinea lo que falte — nunca reescribe un pin ya puesto.

set -euo pipefail
shopt -s nullglob

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh

REQUIREMENTS="addons/requirements.txt"

# --- Bootstrap desde la plantilla ---
# No se versiona —es local al deployment, como addons.txt—, así que se copia una vez.

require_requirements() {
  if [ ! -f "$REQUIREMENTS" ]; then
    ui_bad "no existe $REQUIREMENTS" "cp $REQUIREMENTS.example $REQUIREMENTS — y después 'make addons-deps'"
    exit 1
  fi
}

# --- Manifiestos ---
# Una fila por __manifest__.py bajo cada categoría; el layout lo fija entrypoint.sh.

manifest_files() {
  local category
  for category in $(sed -n 's/^for category in \(.*\); do/\1/p' stacks/odoo/image/entrypoint.sh); do
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

# --- Comparación declarado vs pineado ---
# Un solo cómputo de cada lado; deja MISSING/ORPHANS para no recalcularlos una segunda vez.

comparar_nombres() {
  local declared pinned
  declared=$(declared_names) || true
  pinned=$(pinned_names) || true
  MISSING=$(comm -23 <(printf '%s' "$declared") <(printf '%s' "$pinned"))
  ORPHANS=$(comm -13 <(printf '%s' "$declared") <(printf '%s' "$pinned"))
}

# --- check: sin red, sin Docker ---
# Falla si requirements.txt no cubre lo declarado en los manifiestos; avisa si sobran pines.

cmd_check() {
  require_requirements
  comparar_nombres
  ui_plan_start "pydeps check"
  ui_step 1 "Verificación de que $REQUIREMENTS cubra las external_dependencies declaradas."
  ui_plan_end
  if [ -n "$MISSING" ]; then
    ui_bad "pydeps check: faltan en $REQUIREMENTS" "$(tr '\n' ' ' <<<"$MISSING")"
    echo
    return 1
  fi
  ui_ok "pydeps check: $REQUIREMENTS cubre lo que declaran los addons"
  [ -n "$ORPHANS" ] && ui_warn "pineados de más, ningún addon los declara" "$(tr '\n' ' ' <<<"$ORPHANS")"
  echo
  return 0
}

# --- sync: resuelve contra la imagen base y pinea lo que falte ---
# --no-deps a propósito: pinea solo lo declarado, las transitivas las resuelve pip en build time.

cmd_sync() {
  local missing image reporte resueltos pedidos resueltos_n

  require_requirements
  comparar_nombres
  missing="$MISSING"
  ui_plan_start "pydeps sync"
  if [ -z "$missing" ]; then
    ui_step 1 "Nada nuevo que pinear en $REQUIREMENTS."
    ui_ok "pydeps sync: nada nuevo que pinear"
  else
    image=$(sed -n 's/^FROM \(.*\)$/\1/p' stacks/odoo/image/Dockerfile | head -1)
    pedidos=$(wc -l <<<"$missing" | tr -d ' ')
    ui_step 1 "Resolución de $pedidos paquete(s) contra $image."

    # --- --ignore-installed ---
    # Sin esto, un paquete que ya trae la imagen base (vía apt) queda "satisfied" y no se pinea.

    if ! reporte=$(docker run --rm "$image" \
        pip install --break-system-packages --dry-run --quiet --no-deps --ignore-installed \
          --report - $missing 2>&1); then
      ui_bad "pydeps sync: no se pudo resolver contra $image" "$(tail -1 <<<"$reporte")"
      ui_plan_end
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

  ui_plan_end
  [ -n "$ORPHANS" ] && ui_warn "pineados de más, ningún addon los declara" "$(tr '\n' ' ' <<<"$ORPHANS")"
  echo
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
