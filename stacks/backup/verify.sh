#!/usr/bin/env bash
# Qué se espera del stack backup. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"
META_DIR="${RUNTIME_STATE_DIR:-state}/meta"

  # --- ¿Este entorno respalda, o solo restaura? ---
  # La composición distingue el backup permanente del servicio bajo restore.

respalda() {
  contexto_compose config --services 2>/dev/null | grep -qx backup
}

restaura() {
  local servicios
  perfil_declarado restore || return 1
  servicios=$(contexto_compose_perfiles restore config --services 2>/dev/null) || return 1
  printf '%s\n' "$servicios" | grep -qx backup
}

v_backup() {
  titulo "backup"

  if respalda; then
    sano backup
  else
    omitir "backup levantado" "este entorno solo restaura — el servicio corre a demanda"
    if restaura; then
      ok "perfil restore con backup declarado"
    else
      bad "perfil restore con backup declarado" \
        "el runtime no ofrece backup bajo restore; no se permite saltar el perfil con docker compose run"
      return
    fi
  fi

  # --- El repositorio está declarado ---
  # r2.env es opcional para que Compose y los tests funcionen antes del bootstrap.

  sin_placeholder "r2.env con el repositorio real" \
    stacks/backup/config/r2.env 'TU_ENDPOINT|TU_BUCKET'

  # --- El endpoint es un hostname de R2, no solo el account ID ---
  # El sufijo completo evita aceptar un account ID que fallará al resolver DNS.

  if [ -f stacks/backup/config/r2.env ]; then
    expect "el endpoint de r2.env termina en .r2.cloudflarestorage.com" \
      ".r2.cloudflarestorage.com" grep RESTIC_REPOSITORY stacks/backup/config/r2.env
  else
    omitir "el endpoint de r2.env termina en .r2.cloudflarestorage.com" \
      "falta stacks/backup/config/r2.env"
  fi

  # --- Repositorio alcanzable ---
  # El backup permanente exige snapshots de su proyecto; restore solo exige acceso.

  if respalda; then
    expect "repo de restic con snapshots de este stack" "$COMPOSE_PROJECT_NAME" \
      contexto_compose exec -T backup restic snapshots --latest 1
  else
    expect "repo de restic alcanzable, con algo que restaurar" "snapshots" \
      contexto_compose run --rm --entrypoint restic -T backup snapshots --latest 1
  fi

  # --- Las dos mitades en el mismo snapshot ---
  # Un snapshot debe contener dump y filestore para que la restauración sea válida.

  local rutas
  if ! respalda; then
    omitir "el snapshot trae la base y el filestore" "este entorno no escribe snapshots"
  elif ! corriendo backup; then
    omitir "el snapshot trae la base y el filestore" "$(motivo backup)"
  else
    # `snapshots latest` compara el último snapshot de cada grupo de paths.
    # Se evita `--latest 1`, que podría ocultar la falta reciente de una mitad.
    rutas=$(contexto_compose exec -T backup restic snapshots latest --json 2>/dev/null)
    case "$rutas" in
      *'/data/dump'*)
        case "$rutas" in
          *'/data/odoo'*) ok "el snapshot trae la base y el filestore" ;;
          *) bad "el snapshot trae la base y el filestore" "falta /data/odoo — el filestore no entró" ;;
        esac ;;
      *) bad "el snapshot trae la base y el filestore" \
             "falta /data/dump — se respaldó el filestore sin la base" ;;
    esac
  fi

  # --- Procedencia ejecutada del snapshot ---
  # Metadata versión 2 exige la fotografía del arranque; registros anteriores son solo diagnóstico.
  local metadata_version snapshot_id startup_snapshot provenance_error
  metadata_version=""
  snapshot_id=""
  if [ -s "$META_DIR/last-backup.json" ]; then
    read -r metadata_version snapshot_id < <(python3 - "$META_DIR/last-backup.json" <<'PY' 2>/dev/null || true
import json
import pathlib
import sys

try:
    data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError):
    raise SystemExit(1)
print(data.get("metadata_version", ""), data.get("snapshot_id", ""))
PY
    )
  fi
  if ! respalda; then
    omitir "procedencia ejecutada del snapshot presente" "este entorno no escribe snapshots"
  elif [ "$metadata_version" = 2 ] && [ -n "$snapshot_id" ]; then
    startup_snapshot=$(contexto_compose exec -T backup restic dump "$snapshot_id" \
      /data/meta/addons-startup.json 2>/dev/null || true)
    provenance_error=$(python3 - "$startup_snapshot" "$ENTORNO" "$ODOO_EDITION" <<'PY' 2>/dev/null || true
import json
import sys

try:
    data = json.loads(sys.argv[1])
except (json.JSONDecodeError, TypeError):
    print("el snapshot no contiene addons-startup.json válido")
    raise SystemExit
if data.get("entorno") != sys.argv[2] or data.get("edition") != sys.argv[3]:
    print("la selección ejecutada pertenece a otro entorno o edición")
elif not isinstance(data.get("addons"), dict):
    print("la selección ejecutada no contiene el inventario de addons")
PY
    )
    if [ -z "$provenance_error" ]; then
      ok "procedencia ejecutada del snapshot presente"
    else
      bad "procedencia ejecutada del snapshot presente" "$provenance_error"
    fi
  elif [ -s "$META_DIR/addons.txt" ] || [ -s "$META_DIR/last-backup.json" ]; then
    aviso "procedencia ejecutada del snapshot presente" \
      "metadata histórica disponible solo para diagnóstico; no representa una selección aplicable"
  else
    bad "procedencia ejecutada del snapshot presente" \
      "falta metadata del último backup; ejecutar ENTORNO=$ENTORNO make backup-run"
  fi

  # --- Timers ---
  # El diario respalda y purga; el mensual verifica integridad del repositorio.

  timer_activo backup-daily
  timer_activo backup-monthly
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_backup
resumen
