#!/usr/bin/env bash
# Qué se espera del stack backup. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_backup() {
  titulo "backup"

  sano backup

  # --- El repositorio está declarado ---
  # r2.env es el único config que se declara con required: false, para que un
  # checkout sin bootstrapear igual resuelva `docker compose config` y pueda
  # correr los tests. El precio es que su ausencia no rompe ahí, y lo atrapa acá:
  # sin RESTIC_REPOSITORY, restic falla recién cuando alguien intenta respaldar.

  sin_placeholder "r2.env con el repositorio real" \
    stacks/backup/config/r2.env 'TU_ENDPOINT|TU_BUCKET'

  # --- Repositorio alcanzable, con snapshots de ESTE stack ---
  # restic agrupa por (host, paths) y el hostname sale del proyecto: pedir el
  # nombre propio distingue "el repo tiene snapshots" de "los tiene MI stack".

  expect "repo de restic con snapshots de este stack" "$COMPOSE_PROJECT_NAME" \
    docker compose exec -T backup restic snapshots --latest 1

  # --- Las dos mitades en el mismo snapshot ---
  # Es la propiedad que reemplaza al procedimiento de respaldar en orden. Un
  # snapshot con el filestore y sin el dump restaura una base que no existe.

  local rutas
  if ! corriendo backup; then
    omitir "el snapshot trae la base y el filestore" "$(motivo backup)"
  else
    # `snapshots latest`, no `--latest 1`: restic agrupa por (host, paths), así que
    # --latest 1 devuelve el más nuevo DE CADA GRUPO. Se midió: un backup que se
    # olvidaba el dump pasaba igual, porque el snapshot viejo con el dump seguía
    # apareciendo en la respuesta y tapaba al nuevo.
    rutas=$(docker compose exec -T backup restic snapshots latest --json 2>/dev/null)
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

  if [ -s state/meta/addons.txt ]; then ok "registro de addons del snapshot presente"
  else aviso "registro de addons del snapshot presente" "state/meta/addons.txt vacío — lo escribe make backup"; fi

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
