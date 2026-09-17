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

  # --- Registro de addons en el snapshot ---
  # Sin pineo por commit, es lo único que dice a qué código corresponde el backup.

  if ! respalda; then
    omitir "registro de addons del snapshot presente" "este entorno no escribe snapshots"
  elif [ -s "$META_DIR/addons.txt" ]; then ok "registro de addons del snapshot presente"
  else aviso "registro de addons del snapshot presente" "$META_DIR/addons.txt vacío — lo escribe make backup-run"; fi

  # --- Procedencia de imágenes ---
  # El snapshot debe poder reconstruir qué imagen estaba activa y cuál era la anterior.
  if ! respalda; then
    omitir "procedencia de imágenes del snapshot presente" "este entorno no escribe snapshots"
  elif [ -s "$META_DIR/images.json" ] && grep -q '"Actual"' "$META_DIR/images.json"; then
    ok "procedencia de imágenes del snapshot presente"
  else
    aviso "procedencia de imágenes del snapshot presente" "$META_DIR/images.json vacío — lo escribe make backup-run"
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
