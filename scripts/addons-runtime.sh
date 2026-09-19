#!/usr/bin/env bash
# Contratos del runtime de addons
# Inicializa y valida los árboles montados por los tres entornos.
set -euo pipefail

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh

# Contexto seleccionado
# Los comandos de consumo cargan el runtime sin imponer ENTORNO al bootstrap global.
cargar_contexto() {
  . scripts/lib/contexto.sh
  contexto_iniciar
}

# Referencia base de Odoo
# Conserva el nombre completo declarado por el primer FROM del Dockerfile.
odoo_base_actual() {
  awk 'toupper($1) == "FROM" { print $2; exit }' stacks/odoo/image/Dockerfile
}

# Diagnóstico de permisos
# Python mantiene la lectura de uid, gid y modo igual en Linux y macOS.
directorio_custom_valido() {
  python3 - "$1" "$2" "$3" <<'PY'
import os
import stat
import sys

path, owner, expected_mode = sys.argv[1], int(sys.argv[2]), int(sys.argv[3], 8)
try:
    value = os.stat(path, follow_symlinks=False)
except OSError:
    raise SystemExit(1)
valid = stat.S_ISDIR(value.st_mode)
valid = valid and value.st_uid == owner and value.st_gid == 65532
valid = valid and stat.S_IMODE(value.st_mode) == expected_mode
raise SystemExit(0 if valid else 1)
PY
}

# Inicialización de mounts
# El operador conserva ownership y el receptor escribe mediante el grupo fijo 65532.
cmd_init() {
  local entorno addons custom enterprise operador comando fallos=0 modo=2775
  operador=$(id -u)
  [ "$(uname -s)" != Darwin ] || modo=0775
  for entorno in desarrollo staging produccion; do
    addons="$PWD/runtime/$entorno/addons"
    custom="$addons/custom"
    enterprise="$addons/enterprise"
    mkdir -p "$addons" "$enterprise"
    if [ ! -e "$custom" ]; then
      install -d -o "$operador" -g 65532 -m "$modo" "$custom" 2>/dev/null || true
    fi
    if ! directorio_custom_valido "$custom" "$operador" "$modo"; then
      comando="sudo install -d -o $operador -g 65532 -m 2775 '$custom'"
      ui_bad "permisos incompatibles en runtime/$entorno/addons/custom" "$comando" >&2
      fallos=1
      continue
    fi
    ui_ok "runtime/$entorno/addons/custom listo"
  done
  [ "$fallos" -eq 0 ]
}

# Validación del candidato
# Reutiliza la comprobación de catálogo, commit y tree del publicador sin mutar código.
cmd_validate() {
  cargar_contexto
  CANDIDATE_LOCK_HELD=1 scripts/addons.sh status >/dev/null
  if [ "$ODOO_EDITION" = enterprise ]; then
    CANDIDATE_LOCK_HELD=1 scripts/addons.sh enterprise-validate "$TAG" >/dev/null
  fi
  ui_ok "addons de $ENTORNO íntegros"
}

# Inventario del runtime
# Emite JSON derivado de los marcadores y del checkout Enterprise seleccionado.
cmd_inventory() {
  cargar_contexto
  cmd_validate >/dev/null
  python3 - "$ENTORNO" "$ODOO_EDITION" "$TAG" "$RUNTIME_DIR/addons" <<'PY'
import json
import pathlib
import subprocess
import sys

environment, edition, tag, root_arg = sys.argv[1:]
root = pathlib.Path(root_arg)
addons = {}
for candidate in sorted((root / "custom").glob("*")):
    if not candidate.is_dir():
        continue
    commit = (candidate / ".candidate-commit").read_text(encoding="ascii").strip()
    tree = (candidate / ".candidate-tree").read_text(encoding="ascii").strip()
    addons[candidate.name] = {"commit": commit, "tree": tree}
enterprise = None
if edition == "enterprise":
    checkout = root / "enterprise"
    enterprise = {
        "tag": tag,
        "commit": subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
        ).strip(),
    }
payload = {
    "entorno": environment,
    "edition": edition,
    "addons": addons,
    "enterprise": enterprise,
}
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
}

# Compatibilidad de imagen
# Exige metadata de la imagen seleccionada y compara base, entradas y lock antes de Compose.
cmd_preflight() {
  local base inputs lock builds
  cargar_contexto
  cmd_validate >/dev/null
  base=$(odoo_base_actual)
  inputs="$RUNTIME_DIR/addons/requirements.inputs.sha256"
  lock="$RUNTIME_DIR/addons/requirements.lock.sha256"
  builds="$PWD/runtime/addons/builds/$ENTORNO"
  [ -s "$inputs" ] && [ -s "$lock" ] || {
    ui_bad "faltan huellas de dependencias de $ENTORNO" \
      "ejecutar ENTORNO=$ENTORNO make addons-deps y construir una imagen compatible" >&2
    return 1
  }
  if ! python3 - "$builds" "${ODOO_IMAGE:-}" "$base" "$inputs" "$lock" <<'PY'
import json
import pathlib
import sys

builds_arg, image, base, inputs_path, lock_path = sys.argv[1:]
if not image:
    print("addons-runtime: falta ODOO_IMAGE", file=sys.stderr)
    raise SystemExit(1)
metadata = None
for path in sorted(pathlib.Path(builds_arg).glob("*/image.json")):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        continue
    if value.get("tag") == image:
        metadata = value
        break
if metadata is None:
    print(f"addons-runtime: falta metadata para {image}; ejecutar make build", file=sys.stderr)
    raise SystemExit(1)
expected = {
    "odoo_base": base,
    "requirements_inputs_sha256": pathlib.Path(inputs_path).read_text(encoding="ascii").strip(),
    "requirements_lock_sha256": pathlib.Path(lock_path).read_text(encoding="ascii").strip(),
}
differences = [key for key, value in expected.items() if metadata.get(key) != value]
if differences:
    print(
        "addons-runtime: imagen incompatible en " + ", ".join(differences) + "; ejecutar make build",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
  then
    return 1
  fi
  ui_ok "imagen y addons de $ENTORNO compatibles"
}

# Interfaz de comandos
# Mantiene explícita la única mutación de bootstrap disponible en este script.
case "${1:-}" in
  init) cmd_init ;;
  validate) cmd_validate ;;
  inventory) cmd_inventory ;;
  preflight) cmd_preflight ;;
  *) printf 'Uso: %s init|validate|inventory|preflight\n' "$(basename "$0")" >&2; exit 2 ;;
esac
