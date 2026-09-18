#!/usr/bin/env bash
# Qué se espera del stack odoo. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"
. scripts/lib/odoo-report.sh

ODOO_CONF=stacks/odoo/config/odoo.conf
ODOO_DOCKERFILE=stacks/odoo/image/Dockerfile
ODOO_ENTRYPOINT=stacks/odoo/image/entrypoint.sh
if odoo_report_resolve_urls; then
  ODOO_REPORT_URLS_OK=1
else
  ODOO_REPORT_URLS_OK=0
fi

v_odoo() {
  titulo "odoo"

  sano odoo

  log_limpio "odoo sin errores de permisos" 'permission denied' "" odoo

  # --- smtp_server realmente cargado ---
  # El entrypoint carga SMTP desde el runtime; ODOO_DISABLE_SMTP permite dejarlo vacío.

  if ! smtp_activo; then
    omitir "smtp_server cargado en el runtime conf" \
      "este stack fuerza ODOO_DISABLE_SMTP — smtp_server vacío es lo esperado"
  elif ! corriendo odoo; then
    omitir "smtp_server cargado en el runtime conf" "$(motivo odoo)"
  else
    expect "smtp_server cargado en el runtime conf" "smtp_server = " \
      contexto_compose exec -T odoo grep "^smtp_server = .\+" /tmp/odoo-runtime.conf
  fi

  if ! corriendo odoo; then
    omitir "report.url configurado" "$(motivo odoo)"
    omitir "web.base.url congelado" "$(motivo odoo)"
    omitir "REPORT_URL accesible desde Odoo" "$(motivo odoo)"
  else
    expect "report.url configurado" "$REPORT_URL" contexto_compose exec -T postgres psql -U odoo -d odoo -Atc \
      "SELECT value FROM ir_config_parameter WHERE key = 'report.url'"
    if [ "$ODOO_REPORT_URLS_OK" -eq 1 ]; then
      expect "web.base.url configurado" "$PUBLIC_BASE_URL" contexto_compose exec -T postgres psql -U odoo -d odoo -Atc \
        "SELECT value FROM ir_config_parameter WHERE key = 'web.base.url'"
    else
      aviso "web.base.url configurado" "$ODOO_REPORT_URL_ERROR"
    fi
    expect "web.base.url congelado" "True" contexto_compose exec -T postgres psql -U odoo -d odoo -Atc \
      "SELECT value FROM ir_config_parameter WHERE key = 'web.base.url.freeze'"
    expect "REPORT_URL accesible desde Odoo" "200" contexto_compose exec -T odoo \
      curl -sS -o /dev/null -w '%{http_code}' "$REPORT_URL/web/health"
  fi

  if ! corriendo odoo; then
    omitir "odoo sirve en :8069" "$(motivo odoo)"
  else
    expect "odoo sirve en :8069" "200" contexto_compose exec -T odoo \
      curl -sS -o /dev/null -w '%{http_code}' http://localhost:8069/web/login
  fi

  # --- Selector único y procedencia ---
  # Compose y la metadata del build deben identificar la misma imagen local.
  local selector metadata_dir metadata compose_image
  selector="${ODOO_IMAGE:-}"
  if [[ "$selector" =~ ^local/odoo:[0-9]+([.][0-9]+)*-(desarrollo|staging|produccion)-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}$ ]]; then
    ok "ODOO_IMAGE tiene tag explícito"
  else
    bad "ODOO_IMAGE tiene tag explícito" "referencia ausente, inicial o flotante: ${selector:-vacía}"
  fi
  if [ -n "$selector" ] && docker image inspect "$selector" >/dev/null 2>&1; then
    ok "ODOO_IMAGE existe localmente"
  else
    bad "ODOO_IMAGE existe localmente" "no existe ${selector:-la imagen seleccionada}"
  fi

  compose_image=$(contexto_compose config 2>/dev/null | awk '
    /^  odoo:/ { dentro=1; next }
    dentro && /^  [a-z]/ { exit }
    dentro && /^[[:space:]]+image: / { sub(/^[[:space:]]+image: /, ""); print; exit }
  ')
  if [ -n "$selector" ] && [ "$compose_image" = "$selector" ]; then
    ok "Compose usa ODOO_IMAGE"
  else
    bad "Compose usa ODOO_IMAGE" "Compose=${compose_image:-ausente}; selector=${selector:-ausente}"
  fi

  metadata_dir="$(cd "$RUNTIME_DIR/../addons/builds/$ENTORNO" 2>/dev/null && pwd -P || true)"
  metadata=""
  if [ -n "$metadata_dir" ]; then
    while IFS= read -r candidato; do
      if python3 - "$candidato" "$selector" <<'PY' >/dev/null 2>&1
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if data.get("tag") == sys.argv[2] else 1)
PY
      then
        metadata="$candidato"
        break
      fi
    done < <(find "$metadata_dir" -mindepth 2 -maxdepth 2 -name image.json -type f -print 2>/dev/null | sort)
  fi
  if [ -n "$metadata" ] && python3 - "$metadata" "$selector" "$ODOO_EDITION" "$TAG" <<'PY'
import json, sys
path, selector, edition, edition_tag = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
required = ("tag", "digest", "edition", "edition_tag", "odoo_version", "base_image", "infra_commit", "addons", "built_at")
missing = [key for key in required if key not in data or data[key] in (None, "")]
if missing or data.get("tag") != selector or data.get("edition") != edition or data.get("edition_tag") != edition_tag:
    raise SystemExit(1)
PY
  then
    ok "procedencia técnica de ODOO_IMAGE completa"
  else
    bad "procedencia técnica de ODOO_IMAGE completa" "falta metadata, está incompleta o no coincide con el runtime"
  fi

  # --- Rutas internas ---
  # El compose no puede montar el checkout ni el volumen histórico de addons.
  local compose_odoo
  compose_odoo=$(contexto_compose config 2>/dev/null | sed -n '/^  odoo:/,/^  [a-z]/p')
  if printf '%s\n' "$compose_odoo" | grep -qE '/mnt/extra-addons|/addons([/:]|$)'; then
    bad "addons dentro de la imagen" "Compose monta código de addons desde el host"
  else
    ok "addons dentro de la imagen"
  fi
  if [ -d stacks/odoo/image ] && grep -q '/opt/odoo/enterprise' stacks/odoo/image/Dockerfile \
      && grep -q '/opt/odoo/custom' stacks/odoo/image/Dockerfile; then
    ok "Dockerfile copia Enterprise y dominios a rutas internas"
  else
    bad "Dockerfile copia Enterprise y dominios a rutas internas" "faltan rutas internas de fotografía"
  fi

  # --- Binds ---
  # Nivel 1: solo por nombre dentro de la red app. El 8069 y el bus salen por nginx.

  sin_publicar odoo 8069
  sin_publicar odoo 8072
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_odoo
resumen
