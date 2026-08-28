#!/usr/bin/env bash
# Corrida de backup. Se invoca a mano (make backup-run / make backup-integrity) o desde los
# timers de systemd. Cualquier paso que falle aborta la corrida entera, lo que deja
# exit code != 0 y dispara el OnFailure= de la unit.
#
# Corre en el HOST, no adentro del contenedor: necesita docker compose para hablarle
# tanto a postgres (el dump) como a backup (restic).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../.."
. scripts/lib/ui.sh

if [ -f .env ]; then set -a; . ./.env; set +a; fi

MODE="${1:-daily}"

# --- Endpoint de R2 válido, antes de tocar nada ---
# sin_placeholder (backup-verify) solo descarta el literal TU_ENDPOINT — un valor
# cargado a mano pero incompleto (el account ID sin el sufijo .r2.cloudflarestorage.com,
# por ejemplo) pasa esa verificación igual. Sin este chequeo, restic lo descubre
# recién reintentando contra DNS durante minutos, después de haber dumpeado la base
# para nada.

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
# GFS, la misma que usa Odoo.sh para sus clientes: 7 diarios, 4 semanales, 3
# mensuales. La hace `forget` en la corrida diaria — en restic todo snapshot es
# completo, así que no hace falta una corrida distinta por cadencia.
#
# Un solo lugar: con pgBackRest afuera ya no hay una segunda retención que cruzar.

KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=3

# --- Umbral de aviso del dump ---
# pg_dump relee la base entera en cada corrida. Cuando ese tiempo se va de mano,
# la estrategia de snapshot dejó de alcanzar y toca reconsiderarla (ver
# docs/modular-architecture.md). Se avisa, no se falla: es una señal, no una avería.

DUMP_AVISO_SEGUNDOS=1800

DUMP_PATH=/dumps/odoo.sql

# --- Lock ---
# Evita catch-ups solapados (Persistent=true); sobre el directorio, no un archivo,
# para servir a root y al operador.

if command -v flock >/dev/null 2>&1; then
  exec 9<.
  flock -w 3600 9
else
  ui_warn "flock no disponible (macOS)" "corrida sin serializar" >&2
fi

res() { docker compose exec -T backup restic "$@"; }
pg()  { docker compose exec -T postgres "$@"; }

# --- Marca de éxito ---
# El exit code no es consultable desde Prometheus; esta marca sí. Escritura atómica:
# el colector de textfile puede leer en cualquier momento y un archivo a medias lo rompe.

marcar_exito() {
  local dir="state/textfile" tmp
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.backup.XXXXXX")
  {
    echo "# HELP odoo_backup_last_success_timestamp_seconds Fin de la ultima corrida exitosa."
    echo "# TYPE odoo_backup_last_success_timestamp_seconds gauge"
    echo "odoo_backup_last_success_timestamp_seconds{modo=\"$1\"} $(date +%s)"
  } > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$dir/backup-$1.prom"
}

# --- Registro de addons ---
# Sin pineo por commit, el snapshot necesita decir a qué código corresponde.
# Informativo: un fallo acá no aborta el backup — tolerante y best-effort.

registrar_addons() {
  local dir="state/meta" tmp
  mkdir -p "$dir" 2>/dev/null || { ui_warn "no se pudo crear $dir" "backup sigue sin el registro de addons" >&2; return 0; }
  tmp=$(mktemp "$dir/.addons.XXXXXX" 2>/dev/null) || { ui_warn "no se pudo escribir el registro de addons" "" >&2; return 0; }
  if scripts/addons.sh status 2>/dev/null | grep -E '^(enterprise|custom-addons|oca|third-party)[[:space:]]' > "$tmp"; then
    chmod 644 "$tmp"
    mv "$tmp" "$dir/addons.txt"
  else
    ui_warn "no se pudo generar el registro de addons" "" >&2
    rm -f "$tmp"
  fi
  return 0
}

# --- Dump de la base ---
# SIN COMPRIMIR, y no es un descuido: comprimido, zlib cambia el flujo de bytes
# globalmente ante cualquier modificación y la deduplicación de restic cae a cero
# — subiría el archivo entero todas las noches. Con texto plano, restic dedupe
# los bloques que no cambiaron.
#
# Al volumen `dumps`, que postgres monta rw y backup monta ro: así el dump y el
# filestore entran en el MISMO snapshot y la consistencia es una propiedad del
# backup, no un procedimiento que hay que recordar.

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
    # La base referencia archivos que solo existen en el filestore. Respaldarlos
    # por separado convierte la consistencia en algo que hay que recordar.

    ui_step 1 "Dump de la base y el filestore en un snapshot restic, con retención GFS aplicada."
    validar_endpoint
    dump_base
    registrar_addons
    res backup /data/odoo /data/dump /data/meta --exclude=/data/odoo/sessions
    res forget --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" \
               --keep-monthly "$KEEP_MONTHLY" --prune
    marcar_exito daily
    ;;
  check)
    # --- Integridad del repositorio ---
    # --read-data-subset lee datos REALES, no solo metadata: es lo único que
    # detecta corrupción silenciosa, que ningún backup exitoso revela. Un
    # repositorio corrupto se descubre al restaurar, que es el peor momento.

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
echo
ui_step 2 "Finalizado."
ui_ok "backup $MODE listo"
echo
