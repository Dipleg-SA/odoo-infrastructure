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

# --- Registro de addons ---
# El snapshot registra el código de addons que estaba montado.

registrar_addons() {
  local dir="$META_DIR" tmp error detalle estado
  mkdir -p "$dir" 2>/dev/null || { ui_warn "no se pudo crear $dir" "backup sigue sin el registro de addons" >&2; return 0; }
  tmp=$(mktemp "$dir/.addons.XXXXXX" 2>/dev/null) || { ui_warn "no se pudo escribir el registro de addons" "" >&2; return 0; }
  error=$(mktemp "$dir/.addons-error.XXXXXX" 2>/dev/null) || { ui_warn "no se pudo escribir el diagnóstico de addons" "" >&2; rm -f "$tmp"; return 0; }
  if scripts/addons.sh status > "$tmp" 2> "$error"; then
    if grep -E '^(enterprise:|[[:alnum:]_.-]+[[:space:]]+(publicado|sin candidato)[[:space:]]+)' "$tmp" > "$tmp.registro"; then
      chmod 644 "$tmp.registro"
      mv -f "$tmp.registro" "$dir/addons.txt"
    else
      ui_warn "no se pudo generar el registro de addons" "scripts/addons.sh status no informó worktrees" >&2
      rm -f "$tmp.registro"
    fi
  else
    estado=$?
    detalle=$(tr '\n' ' ' < "$error")
    ui_warn "no se pudo generar el registro de addons" \
      "scripts/addons.sh status salió con $estado: ${detalle:-sin diagnóstico}" >&2
  fi
  rm -f "$tmp" "$error"
  return 0
}

# Registro de imágenes
# Actual y Anterior deben entrar en el mismo snapshot que el dump y el filestore.
registrar_imagenes() {
  local tmp="$META_DIR/.images.$$.tmp"
  mkdir -p "$META_DIR"
  if [ -x scripts/image-state.sh ] && [ -n "${ENTORNO:-}" ]; then
    scripts/image-state.sh show > "$tmp"
  else
    printf '%s\n' '{"Nueva":null,"Actual":null,"Anterior":null,"validation":null}' > "$tmp"
  fi
  chmod 644 "$tmp"
  mv -f "$tmp" "$META_DIR/images.json"
}

# Metadata de backup asociado
# Registra de forma atómica el snapshot y la imagen Actual que quedaron respaldados.
registrar_backup_metadata() {
  local backup_json="$1" snapshot_id actual_tag tmp
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

  actual_tag=$(python3 - "$META_DIR/images.json" <<'PY'
import json, sys

try:
    state = json.load(open(sys.argv[1], encoding='utf-8'))
except (OSError, json.JSONDecodeError):
    state = {}
actual = state.get('Actual')
print(actual.get('tag', '') if isinstance(actual, dict) else '')
PY
  )
  mkdir -p "$META_DIR"
  tmp=$(mktemp "$META_DIR/.last-backup.XXXXXX")
  python3 - "$tmp" "$snapshot_id" "$ENTORNO" "$ODOO_EDITION" "$actual_tag" <<'PY'
import json, sys
from datetime import datetime, timezone

path, snapshot_id, entorno, edition, actual_tag = sys.argv[1:]
payload = {
    'snapshot_id': snapshot_id,
    'entorno': entorno,
    'edition': edition,
    'actual_tag': actual_tag or None,
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
    # --- Las dos mitades del estado, en un solo snapshot ---
    # Dump y filestore deben entrar en el mismo snapshot.

    ui_step 1 "Dump de la base y el filestore en un snapshot restic, con retención GFS aplicada."
    validar_endpoint
    dump_base
    registrar_addons
    registrar_imagenes
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
