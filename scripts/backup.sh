#!/usr/bin/env bash
# Corrida de backup de la capa correspondiente. Se invoca a mano (make backup / make backup-full)
# o desde los timers de systemd. Cualquier paso que falle aborta la corrida entera,
# lo que deja exit code != 0 y dispara el OnFailure= de la unit.
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-daily}"

# --- Lock ---
# Evita catch-ups solapados (Persistent=true); sobre el directorio, no un archivo, para servir a root y operador.

if command -v flock >/dev/null 2>&1; then
  exec 9<.
  flock -w 3600 9
else
  echo "aviso: flock no disponible (macOS) — corrida sin serializar" >&2
fi

pgb() { docker compose exec -T -u postgres postgres pgbackrest "$@"; }
res() { docker compose exec -T backup restic "$@"; }

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
# Sin pineo por commit, el snapshot necesita decir a qué código corresponde. Informativo:
# un fallo acá no aborta el backup — mismo criterio que marcar_exito, tolerante y best-effort.

registrar_addons() {
  local dir="state/meta" tmp
  mkdir -p "$dir" 2>/dev/null || { echo "aviso: no se pudo crear $dir — backup sigue sin el registro de addons" >&2; return 0; }
  tmp=$(mktemp "$dir/.addons.XXXXXX" 2>/dev/null) || { echo "aviso: no se pudo escribir el registro de addons" >&2; return 0; }
  if scripts/addons.sh status 2>/dev/null | grep '^production' > "$tmp"; then
    chmod 644 "$tmp"
    mv "$tmp" "$dir/addons.txt"
  else
    echo "aviso: no se pudo generar el registro de addons" >&2
    rm -f "$tmp"
  fi
  return 0
}

case "$MODE" in
  daily)
    # --- Verificación previa ---
    # Valida repo alcanzable y archivado de WAL antes de escribir nada.

    pgb check

    # --- Base de datos ---

    pgb backup --type=diff

    # --- Filestore (siempre después de la base) ---
    # Snapshot más nuevo que el backup deja huérfanos (inocuo); uno más viejo, adjuntos rotos.

    registrar_addons
    res backup /data/odoo /data/meta --exclude=/data/odoo/sessions
    res forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
    marcar_exito daily
    ;;
  monthly)
    # --- Base de datos, full ---

    pgb backup --type=full
    marcar_exito monthly
    ;;
  *)
    echo "uso: $(basename "$0") [daily|monthly]" >&2
    exit 2
    ;;
esac
