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

  # --- Imagen Actual y addons internos ---
  # La imagen declarada y el estado deben apuntar a la misma fotografía inmutable.
  local estado tag digest edition edition_tag
  local estado_runtime
  if estado_runtime=$(scripts/image-state.sh validate-runtime 2>&1); then
    ok "ranuras de imágenes coherentes con el runtime"
  else
    bad "ranuras de imágenes coherentes con el runtime" "$(printf '%s' "$estado_runtime" | tr '\n' ' ')"
  fi
  estado=$(scripts/image-state.sh get Actual 2>/dev/null || true)
  if [ -z "$estado" ] || [ "$estado" = "null" ]; then
    aviso "imagen Actual declarada" "runtime/state/images.json no tiene Actual"
  else
    tag=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])' <<<"$estado" 2>/dev/null || true)
    digest=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])' <<<"$estado" 2>/dev/null || true)
    edition=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("edition", ""))' <<<"$estado" 2>/dev/null || true)
    edition_tag=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("edition_tag", ""))' <<<"$estado" 2>/dev/null || true)
    if [ -z "$tag" ] || [ -z "$digest" ]; then
      bad "procedencia de imagen Actual completa" "faltan tag o digest"
    else
      ok "procedencia de imagen Actual completa"
      printf '    imagen: %s\n    digest: %s\n' "$tag" "$digest"
      if [ "$edition" = "$ODOO_EDITION" ] && [ "$edition_tag" = "$TAG" ]; then
        ok "edición y tag de imagen Actual coherentes"
      else
        bad "edición y tag de imagen Actual coherentes" \
          "imagen=${edition:-desconocida}/${edition_tag:-sin tag}; runtime=$ODOO_EDITION/$TAG"
      fi
      if python3 - "$estado" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
required = ("edition", "edition_tag", "odoo_version", "base_image", "infra_commit", "addons", "built_at")
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit("faltan " + ", ".join(missing))
PY
      then
        ok "procedencia técnica de imagen Actual completa"
      else
        bad "procedencia técnica de imagen Actual completa" "faltan campos de procedencia"
      fi
      if grep -qE '^    image: ' <(contexto_compose config 2>/dev/null) && contexto_compose config 2>/dev/null | grep -q "image: $tag$"; then
        ok "Compose usa la imagen Actual ($tag)"
      else
        bad "Compose usa la imagen Actual" "la referencia declarada no coincide con $tag"
      fi
    fi
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
