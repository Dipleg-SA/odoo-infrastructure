#!/usr/bin/env bash
# Qué se espera del stack postgres. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.
#
# Corre solo (stacks/postgres/verify.sh) o sourceado por scripts/verify-stacks.sh,
# que comparte los contadores y emite un único resumen.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_postgres() {
  titulo "postgres"

  sano postgres

  # --- Acepta conexiones ---
  # pg_isready es lo mínimo: si esto falla, todo lo de Odoo miente sobre su causa.

  if ! corriendo postgres; then
    omitir "postgres acepta conexiones" "$(motivo postgres)"
  else
    expect "postgres acepta conexiones" "accepting connections" \
      docker compose exec -T postgres pg_isready
  fi

  # --- Permisos del secret ---
  # POSTGRES_PASSWORD_FILE apunta a un secret montado: un 600 root-owned lo deja
  # ilegible y el error aparece al arrancar, no al conectar.

  log_limpio "postgres sin errores de permisos" 'permission denied' "" postgres

  # --- Conexiones contra el techo ---
  # db_maxconn de Odoo por sus procesos tiene que entrar en max_connections. Los
  # dos valores viven en archivos de herramientas distintas y nada más los ata:
  # sin pooler, pasarse no encola, Postgres rechaza.

  local maxconn workers cron maxc techo
  maxconn=$(sed -n 's/^db_maxconn[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' stacks/odoo/config/odoo.conf 2>/dev/null | head -1)
  workers=$(sed -n 's/^workers[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' stacks/odoo/config/odoo.conf 2>/dev/null | head -1)
  cron=$(sed -n 's/^max_cron_threads[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' stacks/odoo/config/odoo.conf 2>/dev/null | head -1)
  maxc=$(sed -n 's/^max_connections[[:space:]]*=[[:space:]]*\([0-9]*\).*/\1/p' stacks/postgres/config/postgresql.conf 2>/dev/null | head -1)
  if ! declarado odoo; then
    omitir "las conexiones de Odoo entran en max_connections" "sin odoo en este stack"
  elif [ -z "$maxconn" ] || [ -z "$workers" ] || [ -z "$cron" ] || [ -z "$maxc" ]; then
    aviso "las conexiones de Odoo entran en max_connections" "no se pudieron leer los valores"
  else
    techo=$(( (workers + cron) * maxconn ))
    if [ "$techo" -le "$maxc" ]; then
      ok "las conexiones de Odoo ($techo) entran en max_connections ($maxc)"
    else
      bad "las conexiones de Odoo entran en max_connections" \
          "$techo > $maxc — sin pooler, Postgres rechaza en vez de encolar"
    fi
  fi

  # --- Binds ---
  # Nivel 1: solo por nombre dentro de la red app, nunca publicado.

  sin_publicar postgres 5432
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_postgres
resumen
