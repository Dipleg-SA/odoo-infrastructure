#!/usr/bin/env bash
# Estado de imágenes por entorno
# Persiste Nueva, Actual, Anterior y la procedencia de cada referencia.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/contexto.sh
contexto_iniciar

STATE_FILE="$RUNTIME_STATE_DIR/images.json"

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
  [ -f "$STATE_FILE" ] || write_state '{"Nueva":null,"Actual":null,"Anterior":null,"validation":null}'
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
import json, pathlib, sys
state = pathlib.Path(sys.argv[1])
candidate = sys.argv[2]
try:
    payload = json.loads(candidate) if candidate.lstrip().startswith("{") else json.loads(pathlib.Path(candidate).read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"fotografía inválida: {exc}")
required = {"tag", "digest", "odoo_version", "base_image", "infra_commit", "enterprise_tag", "enterprise_commit", "addons", "built_at"}
if not isinstance(payload, dict) or not required.issubset(payload):
    raise SystemExit("procedencia incompleta")
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
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for key in ("Nueva", "Actual", "Anterior"):
    value = data.get(key)
    if value is not None and not isinstance(value, dict):
        raise SystemExit(f"{key} inválida")
print("estado de imágenes válido")
PY
    ;;
  *)
    printf 'uso: %s show|get <ranura>|write-new <json|archivo>|validate\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
