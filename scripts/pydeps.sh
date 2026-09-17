#!/usr/bin/env bash
# --- Dependencias Python de los addons ---
# check: ¿requirements.txt cubre lo que declaran los manifiestos? Puro host, sin red.
# sync: resuelve versión contra la imagen base y pinea lo que falte — nunca reescribe un pin ya puesto.

set -euo pipefail
shopt -s nullglob

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
contexto_iniciar

REQUIREMENTS="${PYDEPS_REQUIREMENTS:-runtime/addons/requirements.txt}"

# Snapshot del runtime
# Los comandos manuales leen candidatos del entorno; el build puede inyectar otra raíz.
if [ -n "${PYDEPS_SNAPSHOT_ROOT:-}" ]; then
  SNAPSHOT_ENTERPRISE_ROOT="$PYDEPS_SNAPSHOT_ROOT/enterprise"
  SNAPSHOT_CUSTOM_ROOT="$PYDEPS_SNAPSHOT_ROOT/custom"
else
  SNAPSHOT_ENTERPRISE_ROOT="runtime/addons/enterprise"
  SNAPSHOT_CUSTOM_ROOT="runtime/addons/custom/$ENTORNO"
fi

# --- Bootstrap desde la plantilla ---
# No se versiona —es local al deployment—, así que se copia una vez desde runtime/addons.

require_requirements() {
  if [ ! -f "$REQUIREMENTS" ]; then
    ui_bad "no existe $REQUIREMENTS" "cp $REQUIREMENTS.example $REQUIREMENTS — y después 'make addons-deps'"
    exit 1
  fi
}

# --- Manifiestos ---
# Una fila por __manifest__.py bajo cada snapshot; el layout lo fija entrypoint.sh.

manifest_files() {
  local root
  for root in "$SNAPSHOT_ENTERPRISE_ROOT" "$SNAPSHOT_CUSTOM_ROOT"; do
    [ -d "$root" ] || continue
    find "$root" -name __manifest__.py -type f -print 2>/dev/null || true
  done
}

# Validación de manifiestos
# Un archivo inválido detiene check y sync; nunca se interpreta como un addon sin dependencias.
validar_manifiestos() {
  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(manifest_files)
  [ "${#files[@]}" -gt 0 ] || return 0
  python3 - "${files[@]}" <<'PY'
import ast
import sys

invalid = False
for path in sys.argv[1:]:
    try:
        with open(path, encoding="utf-8") as source:
            manifest = ast.literal_eval(source.read())
    except (OSError, SyntaxError, UnicodeError, ValueError) as error:
        print(f"pydeps: manifiesto inválido: {path}: {error}", file=sys.stderr)
        invalid = True
        continue
    if not isinstance(manifest, dict):
        print(f"pydeps: manifiesto inválido: {path}: debe ser un diccionario", file=sys.stderr)
        invalid = True
        continue
    dependencies = manifest.get("external_dependencies", {})
    if not isinstance(dependencies, dict):
        print(f"pydeps: manifiesto inválido: {path}: external_dependencies debe ser un diccionario", file=sys.stderr)
        invalid = True
        continue
    python_dependencies = dependencies.get("python", [])
    if not isinstance(python_dependencies, (list, tuple)) or not all(isinstance(item, str) for item in python_dependencies):
        print(f"pydeps: manifiesto inválido: {path}: external_dependencies.python debe ser una lista de textos", file=sys.stderr)
        invalid = True
if invalid:
    raise SystemExit(1)
PY
}

# --- external_dependencies.python ---
# ast.literal_eval, no exec: un manifiesto es un dict literal, nunca hace falta correrlo.

declared_deps() {
  [ "$#" -eq 0 ] && return 0
  python3 - "$@" <<'PY'
import ast, sys

names = set()
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        manifest = ast.literal_eval(f.read())
    names.update(manifest.get("external_dependencies", {}).get("python", []))

for n in sorted(names):
    print(n)
PY
}

# --- Normalización de nombre (PEP 503, simplificada) ---
# 'Pillow' y 'pillow', o 'python-dateutil' y 'python_dateutil', se tratan igual.

norm() { tr 'A-Z_.' 'a-z--'; }

# Un requisito puede traer un rango (``authlib>=1.6.12``), pero ese rango no
# forma parte de su identidad. Se conserva literal para pasarlo a pip; solo el
# nombre se normaliza al comparar contra requirements.txt.
requirement_name() {
  sed -E 's/^[[:space:]]*([A-Za-z0-9][A-Za-z0-9._-]*).*/\1/' | norm
}

# Distribuciones instalables
# Los manifiestos declaran módulos importables; pip recibe el nombre de su distribución.
distribution_requirement() {
  local requirement="$1" name suffix
  name=$(printf '%s\n' "$requirement" | sed -E 's/^[[:space:]]*([A-Za-z0-9][A-Za-z0-9._-]*).*/\1/')
  suffix=$(printf '%s\n' "$requirement" | sed -E 's/^[[:space:]]*[A-Za-z0-9][A-Za-z0-9._-]*//')
  case "$(printf '%s\n' "$name" | norm)" in
    openssl) printf 'pyOpenSSL%s\n' "$suffix" ;;
    pil) printf 'Pillow%s\n' "$suffix" ;;
    yaml) printf 'PyYAML%s\n' "$suffix" ;;
    dateutil) printf 'python-dateutil%s\n' "$suffix" ;;
    jwt) printf 'PyJWT%s\n' "$suffix" ;;
    magic) printf 'python-magic%s\n' "$suffix" ;;
    ldap) printf 'python-ldap%s\n' "$suffix" ;;
    *) printf '%s\n' "$requirement" ;;
  esac
}

declared_pairs() {
  local files=() f requirement distribution
  while IFS= read -r f; do files+=("$f"); done < <(manifest_files)
  [ "${#files[@]}" -eq 0 ] && return 0

  while IFS= read -r requirement; do
    distribution=$(distribution_requirement "$requirement")
    printf '%s\t%s\n' "$(printf '%s\n' "$distribution" | requirement_name)" "$distribution"
  done < <(declared_deps "${files[@]}")
}

declared_names() {
  declared_pairs | cut -f1 | sort -u
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

# MISSING contiene nombres normalizados. Para resolver, recuperar los requisitos
# originales: pip necesita los puntos de la versión y cualquier otro specifier.
missing_requirements() {
  [ -n "$MISSING" ] || return 0
  awk -F '\t' 'NR == FNR { missing[$1] = 1; next } missing[$1] { print $2 }' \
    <(printf '%s\n' "$MISSING") <(declared_pairs)
}

# --- check: sin red, sin Docker ---
# Falla si requirements.txt no cubre lo declarado en los manifiestos; avisa si sobran pines.

cmd_check() {
  require_requirements
  validar_manifiestos
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
  local missing image reporte resueltos pedidos resueltos_n requirement
  local requests=()

  require_requirements
  validar_manifiestos
  comparar_nombres
  missing=$(missing_requirements)
  ui_plan_start "pydeps sync"
  if [ -z "$missing" ]; then
    ui_step 1 "Nada nuevo que pinear en $REQUIREMENTS."
    ui_ok "pydeps sync: nada nuevo que pinear"
  else
    image=$(sed -n 's/^FROM \(.*\)$/\1/p' stacks/odoo/image/Dockerfile | head -1)
    while IFS= read -r requirement; do requests+=("$requirement"); done <<<"$missing"
    pedidos="${#requests[@]}"
    ui_step 1 "Resolución de $pedidos paquete(s) contra $image."

    # --- --ignore-installed ---
    # Sin esto, un paquete que ya trae la imagen base (vía apt) queda "satisfied" y no se pinea.

    if ! reporte=$(docker run --rm "$image" \
        pip install --break-system-packages --dry-run --quiet --no-deps --ignore-installed \
          --report - "${requests[@]}" 2>&1); then
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
