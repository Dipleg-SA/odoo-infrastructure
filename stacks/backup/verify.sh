#!/usr/bin/env bash
# Qué se espera del stack backup. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

# --- ¿Este entorno respalda, o solo restaura? ---
# Se deriva de la composición, no de una lista: si backup está en la composición
# POR DEFECTO corre siempre y se le puede exigir healthcheck y frescura. Si solo
# aparece bajo perfil —el entrypoint de prueba le pone profiles: [restore]— es un
# one-off y esos dos chequeos fallarían por la razón equivocada.

respalda() {
  docker compose config --services 2>/dev/null | grep -qx backup
}

v_backup() {
  titulo "backup"

  if respalda; then
    sano backup
  else
    omitir "backup levantado" "este entorno solo restaura — el servicio corre a demanda"
  fi

  # --- El repositorio está declarado ---
  # r2.env es el único config que se declara con required: false, para que un
  # checkout sin bootstrapear igual resuelva `docker compose config` y pueda
  # correr los tests. El precio es que su ausencia no rompe ahí, y lo atrapa acá:
  # sin RESTIC_REPOSITORY, restic falla recién cuando alguien intenta respaldar.

  sin_placeholder "r2.env con el repositorio real" \
    stacks/backup/config/r2.env 'TU_ENDPOINT|TU_BUCKET'

  # --- El endpoint es un hostname de R2, no solo el account ID ---
  # sin_placeholder solo descarta el literal TU_ENDPOINT: un valor cargado a mano
  # pero incompleto (el account ID sin .r2.cloudflarestorage.com) pasa esa
  # verificación igual, y recién se nota cuando restic reintenta contra DNS.

  if [ -f stacks/backup/config/r2.env ]; then
    expect "el endpoint de r2.env termina en .r2.cloudflarestorage.com" \
      ".r2.cloudflarestorage.com" grep RESTIC_REPOSITORY stacks/backup/config/r2.env
  else
    omitir "el endpoint de r2.env termina en .r2.cloudflarestorage.com" \
      "falta stacks/backup/config/r2.env"
  fi

  # --- Repositorio alcanzable ---
  # Qué se espera depende del rol del entorno, y por eso la consulta cambia:
  #
  # El que respalda tiene que ver snapshots CON SU PROPIO nombre — restic agrupa
  # por (host, paths) y el hostname sale del proyecto, así que pedirlo distingue
  # "el repo tiene snapshots" de "los tiene MI stack".
  #
  # El que solo restaura lee el repositorio de producción: exigirle su propio
  # nombre fallaría siempre, porque nunca escribió nada ahí. Lo que se verifica es
  # que el repositorio se alcance y tenga de dónde sembrar. Y como su contenedor
  # no está levantado, la consulta va por `run` en vez de `exec`.

  if respalda; then
    expect "repo de restic con snapshots de este stack" "$COMPOSE_PROJECT_NAME" \
      docker compose exec -T backup restic snapshots --latest 1
  else
    expect "repo de restic alcanzable, con algo que restaurar" "snapshots" \
      docker compose run --rm --entrypoint restic -T backup snapshots --latest 1
  fi

  # --- Las dos mitades en el mismo snapshot ---
  # Es la propiedad que reemplaza al procedimiento de respaldar en orden. Un
  # snapshot con el filestore y sin el dump restaura una base que no existe.

  local rutas
  if ! respalda; then
    omitir "el snapshot trae la base y el filestore" "este entorno no escribe snapshots"
  elif ! corriendo backup; then
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

  if ! respalda; then
    omitir "registro de addons del snapshot presente" "este entorno no escribe snapshots"
  elif [ -s state/meta/addons.txt ]; then ok "registro de addons del snapshot presente"
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
