#!/usr/bin/env bash
# Corrida de backup. Se invoca a mano (make backup-run / make backup-integrity) o desde los
# timers de systemd; un fallo aborta y dispara el OnFailure de la unit.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh

# Contexto obligatorio del runtime
# Toda corrida usa exclusivamente el estado y la composición de ENTORNO.
[ -n "${ENTORNO:-}" ] || { ui_bad "falta ENTORNO" "usar ENTORNO=desarrollo, staging o produccion" >&2; exit 2; }
. scripts/lib/contexto.sh
contexto_iniciar
META_DIR="$RUNTIME_STATE_DIR/meta"
compose() { contexto_compose "$@"; }

MODE="${1:-daily}"

# --- Endpoint de R2 válido, antes de tocar nada ---
# Se valida el endpoint antes del dump para evitar una corrida inútil.

validar_endpoint() {
  local repo
  repo=$(sed -n 's/^RESTIC_REPOSITORY=//p' stacks/backup/config/r2.env 2>/dev/null)
  case "$repo" in
    s3:https://*.r2.cloudflarestorage.com/*) ;;
    *) ui_bad "RESTIC_REPOSITORY no es un endpoint de R2 válido" \
         "revisar TU_ENDPOINT en stacks/backup/config/r2.env — tiene que terminar en .r2.cloudflarestorage.com" >&2
       exit 1 ;;
  esac
}

# --- Retención ---
# La corrida diaria aplica la retención GFS sobre snapshots completos de restic.

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=3

# --- Umbral de aviso del dump ---
# Un dump lento es una señal operativa, no un fallo del backup.

DUMP_AVISO_SEGUNDOS=1800

DUMP_PATH=/dumps/odoo.sql

# --- Lock ---
# Evita corridas solapadas de los timers y del operador.

if command -v flock >/dev/null 2>&1; then
  exec 9<.
  flock -w 3600 9
else
  ui_warn "flock no disponible (macOS)" "corrida sin serializar" >&2
fi

res() { compose exec -T backup restic "$@"; }
pg()  { compose exec -T postgres "$@"; }

# --- Marca de éxito ---
# Prometheus lee esta marca mediante el colector textfile.

marcar_exito() {
  local dir="${RUNTIME_STATE_DIR:-state}/textfile" tmp
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.backup.XXXXXX")
  {
    echo "# HELP odoo_backup_last_success_timestamp_seconds Fin de la ultima corrida exitosa."
    echo "# TYPE odoo_backup_last_success_timestamp_seconds gauge"
    echo "odoo_backup_last_success_timestamp_seconds{modo=\"$1\"} $(date +%s)"
  } > "$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$dir/backup-$1.prom"
}

# --- Selección ejecutada ---
# El snapshot registra lo que el contenedor Odoo cargó, no el candidato publicado después.

registrar_addons() {
  local dir="$META_DIR" tmp
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.addons-startup.XXXXXX")
  if ! compose exec -T odoo cat /tmp/odoo-addons-startup.json > "$tmp"; then
    rm -f "$tmp"
    ui_bad "no se pudo leer la selección ejecutada de Odoo" \
      "levantar y verificar Odoo antes de crear el backup" >&2
    return 1
  fi
  if ! python3 - "$tmp" "$ENTORNO" "$ODOO_EDITION" <<'PY'
import json
import pathlib
import sys

path, environment, edition = sys.argv[1:]
try:
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
if data.get("entorno") != environment or data.get("edition") != edition:
    raise SystemExit(1)
addons = data.get("addons")
if not isinstance(addons, dict):
    raise SystemExit(1)
for value in addons.values():
    if not isinstance(value, dict) or not value.get("commit") or not value.get("tree"):
        raise SystemExit(1)
if edition == "enterprise" and not (data.get("enterprise") or {}).get("commit"):
    raise SystemExit(1)
PY
  then
    rm -f "$tmp"
    ui_bad "selección ejecutada de Odoo inválida" \
      "recrear Odoo y ejecutar ENTORNO=$ENTORNO make odoo-verify" >&2
    return 1
  fi
  chmod 644 "$tmp"
  mv -f "$tmp" "$dir/addons-startup.json"
  ui_ok "selección ejecutada de addons registrada"
}

# Metadata de backup asociado
# Registra de forma atómica el snapshot y el selector vigente como diagnóstico.
registrar_backup_metadata() {
  local backup_json="$1" snapshot_id odoo_image tmp
  [ -n "${ENTORNO:-}" ] || return 0
  [ -n "${ODOO_EDITION:-}" ] || return 0

  snapshot_id=$(printf '%s\n' "$backup_json" | python3 -c '
import json, sys

ids = []
for line in sys.stdin:
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    values = value if isinstance(value, list) else [value]
    ids.extend(item.get("snapshot_id") or item.get("id") for item in values if isinstance(item, dict))
print(next((value for value in reversed(ids) if value), ""))
')
  if [ -z "$snapshot_id" ]; then
    ui_bad "backup sin identificador de snapshot" "restic no devolvió snapshot_id; no se registra la transición" >&2
    return 1
  fi

  odoo_image="${ODOO_IMAGE:-}"
  mkdir -p "$META_DIR"
  tmp=$(mktemp "$META_DIR/.last-backup.XXXXXX")
  python3 - "$tmp" "$snapshot_id" "$ENTORNO" "$ODOO_EDITION" "$odoo_image" "$META_DIR/addons-startup.json" <<'PY'
import json, sys
from datetime import datetime, timezone

path, snapshot_id, entorno, edition, odoo_image, startup_path = sys.argv[1:]
with open(startup_path, encoding='utf-8') as source:
    startup = json.load(source)
payload = {
    'metadata_version': 2,
    'snapshot_id': snapshot_id,
    'entorno': entorno,
    'edition': edition,
    'odoo_image': odoo_image or None,
    'addons_startup': startup,
    'created_at': datetime.now(timezone.utc).isoformat(),
}
with open(path, 'w', encoding='utf-8') as output:
    json.dump(payload, output, ensure_ascii=False, sort_keys=True)
    output.write('\n')
PY
  chmod 644 "$tmp"
  mv -f "$tmp" "$META_DIR/last-backup.json"
  ui_ok "snapshot asociado registrado: $snapshot_id"
}

# --- Dump de la base ---
# El dump plano permite que restic deduplique bloques sin comprimir toda la base.

dump_base() {
  local inicio fin dur
  inicio=$(date +%s)
  pg sh -c "pg_dump -U odoo -d odoo --format=plain --no-owner > $DUMP_PATH.tmp && mv $DUMP_PATH.tmp $DUMP_PATH"
  fin=$(date +%s); dur=$((fin - inicio))
  ui_ok "dump de la base listo (${dur}s)"

  if [ "$dur" -ge "$DUMP_AVISO_SEGUNDOS" ]; then
    ui_warn "el dump tardó ${dur}s (umbral ${DUMP_AVISO_SEGUNDOS}s)" \
      "la base creció: revisar si el snapshot sigue siendo la estrategia correcta" >&2
  fi
}

ui_plan_start "backup $MODE"
case "$MODE" in
  daily)
    # --- Las dos mitades de datos, en un solo snapshot ---
    # Dump y filestore deben entrar en el mismo snapshot.

    ui_step 1 "Dump de la base y el filestore en un snapshot restic, con retención GFS aplicada."
    validar_endpoint
    dump_base
    registrar_addons
    backup_json=$(res backup --json /data/odoo /data/dump /data/meta --exclude=/data/odoo/sessions)
    registrar_backup_metadata "$backup_json"
    res forget --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" \
               --keep-monthly "$KEEP_MONTHLY" --prune
    marcar_exito daily
    ;;
  check)
    # --- Integridad del repositorio ---
    # --read-data-subset comprueba datos reales además de metadata.

    ui_step 1 "Verificación de integridad del repositorio de restic (muestra de datos)."
    validar_endpoint
    res check --read-data-subset=5%
    marcar_exito check
    ;;
  *)
    ui_bad "uso: $(basename "$0") [daily|check]" "" >&2
    exit 2
    ;;
esac
ui_plan_end
ui_ok "backup $MODE listo"
echo
