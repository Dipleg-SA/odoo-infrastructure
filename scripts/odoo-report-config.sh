#!/usr/bin/env bash
# Configura las URLs pública e interna que Odoo usa para generar reportes PDF.
#
# web.base.url es para enlaces que salen hacia el navegador. report.url es para
# wkhtmltopdf: se resuelve desde dentro de la red Docker y nunca debe depender
# del puerto publicado por nginx.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
. scripts/lib/odoo-report.sh
contexto_iniciar

if ! odoo_report_resolve_urls; then
  ui_bad "URLs de reportes inválidas" "$ODOO_REPORT_URL_ERROR"
  exit 2
fi

if ! contexto_compose ps -q odoo 2>/dev/null | grep -q .; then
  ui_bad "odoo está corriendo" "levantar la aplicación con make odoo-up"
  exit 2
fi

ui_plan_start "configuración de URLs de Odoo"
ui_step 1 "Esperar Odoo en $REPORT_URL y guardar los parámetros de la base."

esperar_odoo() {
  local listo=0
  for _ in $(seq 1 60); do
    if contexto_compose exec -T odoo curl -fsS "$REPORT_URL/web/health" >/dev/null 2>&1; then
      listo=1
      break
    fi
    sleep 1
  done

  if [ "$listo" -ne 1 ]; then
    ui_bad "Odoo responde en REPORT_URL" "$REPORT_URL/web/health no respondió a tiempo"
    return 1
  fi
  ui_ok "Odoo responde en REPORT_URL"
}

esperar_odoo

leer_parametros() {
  contexto_compose exec -T postgres psql -U odoo -d odoo -AtF '|' \
    -c "SELECT key, COALESCE(value, '')
        FROM ir_config_parameter
        WHERE key IN ('report.url', 'web.base.url', 'web.base.url.freeze')
        ORDER BY key"
}

parametros_coinciden() {
  local data="$1"
  printf '%s\n' "$data" | awk -F '|' \
    -v expected_report_url="$REPORT_URL" \
    -v expected_public_url="$PUBLIC_BASE_URL" \
    'BEGIN { report_ok = 0; public_ok = 0; frozen_ok = 0 }
     $1 == "report.url" && $2 == expected_report_url { report_ok = 1 }
     $1 == "web.base.url" && $2 == expected_public_url { public_ok = 1 }
     $1 == "web.base.url.freeze" && $2 == "True" { frozen_ok = 1 }
     END { exit !(report_ok && public_ok && frozen_ok) }'
}

parametros_actuales=$(leer_parametros) || {
  ui_bad "leer parámetros de Odoo" "PostgreSQL no devolvió ir_config_parameter"
  exit 1
}

if parametros_coinciden "$parametros_actuales"; then
  ui_ok "URLs de reportes ya configuradas; no se reinicia Odoo"
else
  ui_run "guardar URLs de reportes" contexto_compose exec -T postgres psql -U odoo -d odoo -v ON_ERROR_STOP=1 \
    -v report_url="$REPORT_URL" \
    -v public_base_url="$PUBLIC_BASE_URL" <<'SQL'
INSERT INTO ir_config_parameter
    (key, value, create_uid, write_uid, create_date, write_date)
VALUES
    ('report.url', :'report_url', NULL, NULL, now(), now()),
    ('web.base.url', :'public_base_url', NULL, NULL, now(), now()),
    ('web.base.url.freeze', 'True', NULL, NULL, now(), now())
ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    write_uid = NULL,
    write_date = now();
SQL

  parametros_actuales=$(leer_parametros) || {
    ui_bad "verificar URLs de reportes" "PostgreSQL no devolvió los parámetros recién guardados"
    exit 1
  }
  parametros_coinciden "$parametros_actuales" || {
    ui_bad "verificar URLs de reportes" "los valores guardados no coinciden con los esperados"
    exit 1
  }

  # ir.config_parameter queda cacheado en los workers de Odoo. Como este script
  # escribe directamente en PostgreSQL, el reinicio es obligatorio después de
  # un cambio para que el proceso que ejecuta wkhtmltopdf vea los nuevos valores.
  ui_run "reiniciar Odoo para recargar los parámetros" contexto_compose restart odoo
  esperar_odoo
fi

ui_ok "report.url = $REPORT_URL"
ui_ok "web.base.url = $PUBLIC_BASE_URL"
ui_ok "web.base.url.freeze = True"
ui_plan_end
