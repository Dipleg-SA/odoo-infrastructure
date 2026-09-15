#!/usr/bin/env bash
# Estado de imágenes por entorno
# Persiste Nueva, Actual, Anterior y la procedencia de cada referencia.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/contexto.sh
contexto_iniciar

# Exclusión de transiciones
# Promoción, rollback y publicación de Nueva comparten el lock del entorno.
case "${1:-}" in
  write-new|apply|rollback|validate-image|invalidate-rollback|restore-meta)
    if [ "${IMAGE_STATE_LOCK_HELD:-0}" != "1" ] && [ "${CANDIDATE_LOCK_HELD:-0}" != "1" ] \
        && [ -f scripts/lib/candidate-lock.sh ]; then
      . scripts/lib/candidate-lock.sh
      candidate_lock_run "$ENTORNO" -- env IMAGE_STATE_LOCK_HELD=1 "$0" "$@"
      exit $?
    fi
    ;;
esac

STATE_FILE="$RUNTIME_STATE_DIR/images.json"
IMAGE_TAG_PATTERN='^[a-z0-9][a-z0-9./_-]*:[A-Za-z0-9][A-Za-z0-9._-]*$'

# Referencia de imagen válida
# Evita que una etiqueta se convierta en sintaxis ejecutable al cargar compose.env.
validar_tag() {
  [[ "$1" =~ $IMAGE_TAG_PATTERN ]] || {
    printf 'referencia de imagen inválida: %s\n' "$1" >&2
    return 1
  }
}

# Escritura atómica
# Un archivo temporal y rename evitan estados JSON truncados ante un corte.
write_state() {
  local payload="$1" temporal
  mkdir -p "$(dirname "$STATE_FILE")"
  temporal=$(mktemp "${STATE_FILE}.XXXXXX")
  printf '%s\n' "$payload" > "$temporal"
  mv -f "$temporal" "$STATE_FILE"
}

# Estado inicial
# Las tres ranuras existen desde el primer uso para que los lectores no adivinen.
ensure_state() {
  [ -f "$STATE_FILE" ] || write_state '{"Nueva":null,"Actual":null,"Anterior":null,"validation":null,"rollback_blocked":false,"module_operations":[]}'
}

# Transiciones y validación
# Python conserva las ranuras y reemplaza el archivo completo antes de informar éxito.
transition() {
  local action="$1" argument="${2:-}"
  ensure_state
  python3 - "$STATE_FILE" "$action" "$argument" <<'PY'
import datetime, json, os, pathlib, re, sys, tempfile
state, action, argument = sys.argv[1:]
path = pathlib.Path(state)
data = json.loads(path.read_text(encoding="utf-8"))
image_tag = re.compile(r"^[a-z0-9][a-z0-9./_-]*:[A-Za-z0-9][A-Za-z0-9._-]*$")

def validar_ranuras(value):
    for key in ("Nueva", "Actual", "Anterior"):
        slot = value.get(key)
        if slot is not None and (not isinstance(slot, dict) or not isinstance(slot.get("tag"), str) or not image_tag.fullmatch(slot["tag"])):
            raise SystemExit(f"{key} tiene una referencia de imagen inválida")

for key, default in (("Nueva", None), ("Actual", None), ("Anterior", None), ("validation", None), ("rollback_blocked", False), ("module_operations", [])):
    data.setdefault(key, default)
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
if action == "apply":
    if data["Nueva"] is None: raise SystemExit("no hay Nueva para aplicar")
    data["Anterior"], data["Actual"], data["Nueva"] = data["Actual"], data["Nueva"], None
    data["validation"], data["rollback_blocked"] = None, False
elif action == "rollback":
    if data["Anterior"] is None: raise SystemExit("no hay Anterior para reactivar")
    if data.get("rollback_blocked"): raise SystemExit("rollback de imagen bloqueado por una operación de módulos")
    data["Nueva"], data["Actual"], data["Anterior"] = None, data["Anterior"], data["Actual"]
    data["validation"] = {"result": "rollback", "note": argument, "at": now}
elif action == "validate":
    if data["Actual"] is None: raise SystemExit("no hay Actual para validar")
    data["validation"] = {"result": "ok", "note": argument, "at": now}
elif action == "invalidate":
    if data["Actual"] is None: raise SystemExit("no hay Actual para registrar la operación")
    data["rollback_blocked"] = True
    data["module_operations"].append({"operation": argument, "at": now})
elif action == "require-actual":
    if data["Actual"] is None: raise SystemExit("no hay imagen Actual declarada")
elif action == "restore-meta":
    source = pathlib.Path(argument)
    restored = json.loads(source.read_text(encoding="utf-8"))
    for key in ("Actual", "Anterior", "validation"):
        data[key] = restored.get(key)
    data["Nueva"], data["rollback_blocked"] = None, False
    data["module_operations"] = []
else: raise SystemExit("transición inválida")
validar_ranuras(data)
if action != "require-actual":
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        json.dump(data, output, ensure_ascii=False, sort_keys=True); output.write("\n")
    os.replace(temporary, path)
print(json.dumps(data, ensure_ascii=False, sort_keys=True))
PY
}

# Sincronización del selector de Compose
# La referencia que consume Compose queda escrita junto al runtime después de cada transición.
sync_compose_image() {
  local tag="$1"
  validar_tag "$tag"
  python3 - "$RUNTIME_ENV_FILE" "$tag" <<'PY'
import pathlib, shlex, sys
path, tag = pathlib.Path(sys.argv[1]), sys.argv[2]
safe_tag = shlex.quote(tag)
lines = path.read_text(encoding="utf-8").splitlines()
for i, line in enumerate(lines):
    if line.startswith("ODOO_IMAGE="):
        lines[i] = "ODOO_IMAGE=" + safe_tag; break
else:
    lines.extend(["", "# Imagen Odoo", "# Referencia promovida por image-state.sh.", "ODOO_IMAGE=" + safe_tag])
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

case "${1:-}" in
  show)
    ensure_state
    cat "$STATE_FILE"
    ;;
  get)
    ensure_state
    python3 - "$STATE_FILE" "${2:-}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
key = sys.argv[2]
if key not in data:
    raise SystemExit(2)
value = data[key]
print("null" if value is None else json.dumps(value, ensure_ascii=False, sort_keys=True))
PY
    ;;
  write-new)
    [ -n "${2:-}" ] || { printf 'uso: %s write-new <json|archivo>\n' "$(basename "$0")" >&2; exit 2; }
    ensure_state
    python3 - "$STATE_FILE" "$2" <<'PY' > "${STATE_FILE}.payload"
import json, pathlib, re, sys
state = pathlib.Path(sys.argv[1])
candidate = sys.argv[2]
try:
    payload = json.loads(candidate) if candidate.lstrip().startswith("{") else json.loads(pathlib.Path(candidate).read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"fotografía inválida: {exc}")
required = {"tag", "digest", "odoo_version", "base_image", "infra_commit", "enterprise_tag", "enterprise_commit", "addons", "built_at"}
if not isinstance(payload, dict) or not required.issubset(payload):
    raise SystemExit("procedencia incompleta")
if not isinstance(payload.get("tag"), str) or not re.fullmatch(r"^[a-z0-9][a-z0-9./_-]*:[A-Za-z0-9][A-Za-z0-9._-]*$", payload["tag"]):
    raise SystemExit("referencia de imagen inválida")
if not isinstance(payload["addons"], dict):
    raise SystemExit("addons debe ser un mapa de dominios y commits")
data = json.loads(state.read_text(encoding="utf-8"))
data["Nueva"] = payload
print(json.dumps(data, ensure_ascii=False, sort_keys=True))
PY
    write_state "$(cat "${STATE_FILE}.payload")"
    rm -f "${STATE_FILE}.payload"
    ;;
  validate)
    ensure_state
    python3 - "$STATE_FILE" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
image_tag = re.compile(r"^[a-z0-9][a-z0-9./_-]*:[A-Za-z0-9][A-Za-z0-9._-]*$")
for key in ("Nueva", "Actual", "Anterior"):
    value = data.get(key)
    if value is not None and (not isinstance(value, dict) or not isinstance(value.get("tag"), str) or not image_tag.fullmatch(value["tag"])):
        raise SystemExit(f"{key} inválida")
print("estado de imágenes válido")
PY
    ;;
  apply)
    resultado=$(transition apply)
    tag=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Actual"]["tag"])' <<<"$resultado")
    sync_compose_image "$tag"
    printf 'Nueva promovida a Actual: %s\n' "$tag"
    ;;
  rollback)
    resultado=$(transition rollback "${2:-}")
    tag=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Actual"]["tag"])' <<<"$resultado")
    sync_compose_image "$tag"
    printf 'Anterior reactivada como Actual: %s\n' "$tag"
    ;;
  validate-image)
    transition validate "${2:-validación manual}" >/dev/null
    printf 'validación registrada para Actual\n'
    ;;
  invalidate-rollback)
    transition invalidate "${2:-operación de módulos}" >/dev/null
    printf 'rollback de imagen bloqueado: operación de módulos registrada\n'
    ;;
  require-actual)
    transition require-actual >/dev/null
    ;;
  restore-meta)
    [ -n "${2:-}" ] || { printf 'uso: %s restore-meta <archivo>\n' "$(basename "$0")" >&2; exit 2; }
    resultado=$(transition restore-meta "$2")
    tag=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["Actual"]["tag"])' <<<"$resultado")
    sync_compose_image "$tag"
    printf 'procedencia restaurada; Actual: %s\n' "$tag"
    ;;
  *)
    printf 'uso: %s show|get <ranura>|write-new <json|archivo>|validate|apply|rollback|validate-image|invalidate-rollback|require-actual|restore-meta\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
