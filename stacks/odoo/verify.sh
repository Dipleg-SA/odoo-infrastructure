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
  local selector metadata_dir metadata compose_image base inputs lock resultado
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
required = ("tag", "digest", "edition", "edition_tag", "odoo_version", "odoo_base", "infra_commit", "requirements_inputs_sha256", "requirements_lock_sha256", "built_at")
missing = [key for key in required if key not in data or data[key] in (None, "")]
if missing or data.get("tag") != selector or data.get("edition") != edition or data.get("edition_tag") != edition_tag:
    raise SystemExit(1)
PY
  then
    ok "procedencia técnica de ODOO_IMAGE completa"
  else
    bad "procedencia técnica de ODOO_IMAGE completa" "falta metadata, está incompleta o no coincide con el runtime"
  fi

  # --- Compatibilidad de imagen ---
  # La base y las huellas montadas deben ser las mismas con las que se construyó la imagen.
  base=$(awk 'toupper($1) == "FROM" { print $2; exit }' "$ODOO_DOCKERFILE")
  inputs="$RUNTIME_DIR/addons/requirements.inputs.sha256"
  lock="$RUNTIME_DIR/addons/requirements.lock.sha256"
  resultado=""
  if [ -n "$metadata" ] && [ -s "$inputs" ] && [ -s "$lock" ]; then
    resultado=$(python3 - "$metadata" "$base" "$inputs" "$lock" <<'PY' 2>/dev/null || true
import json
import pathlib
import sys

metadata, base, inputs, lock = sys.argv[1:]
data = json.loads(pathlib.Path(metadata).read_text(encoding="utf-8"))
checks = {
    "base": data.get("odoo_base") == base,
    "inputs": data.get("requirements_inputs_sha256") == pathlib.Path(inputs).read_text(encoding="ascii").strip(),
    "lock": data.get("requirements_lock_sha256") == pathlib.Path(lock).read_text(encoding="ascii").strip(),
}
print(" ".join(key for key, valid in checks.items() if not valid))
PY
    )
    if [ -z "$resultado" ]; then
      ok "imagen compatible con base y dependencias"
    else
      bad "imagen compatible con base y dependencias" "difieren ${resultado}; ejecutar ENTORNO=$ENTORNO make build"
    fi
  else
    bad "imagen compatible con base y dependencias" "faltan metadata o huellas; ejecutar ENTORNO=$ENTORNO make addons-deps y make build"
  fi

  # --- Mounts e integridad ---
  # Odoo consume exactamente los dos árboles del entorno como binds de solo lectura.
  local compose_odoo expected_custom expected_enterprise runtime_script
  compose_odoo=$(contexto_compose config 2>/dev/null | sed -n '/^  odoo:/,/^  [a-z]/p')
  expected_custom="$RUNTIME_DIR/addons/custom"
  expected_enterprise="$RUNTIME_DIR/addons/enterprise"
  if python3 - "$expected_custom" "$expected_enterprise" "$compose_odoo" <<'PY' >/dev/null 2>&1
import sys

custom, enterprise, text = sys.argv[1:]
for source, target in ((custom, "/opt/odoo/custom"), (enterprise, "/opt/odoo/enterprise")):
    if f"source: {source}" not in text or f"target: {target}" not in text:
        raise SystemExit(1)
if text.count("read_only: true") < 2 or text.count("create_host_path: false") < 2:
    raise SystemExit(1)
PY
  then
    ok "mounts de addons acotados y de solo lectura"
  else
    bad "mounts de addons acotados y de solo lectura" "Compose debe montar runtime/$ENTORNO/addons/{custom,enterprise} sin escritura ni creación implícita"
  fi

  runtime_script="${ODOO_ADDONS_RUNTIME_SCRIPT:-scripts/addons-runtime.sh}"
  if CANDIDATE_LOCK_HELD=1 "$runtime_script" validate >/dev/null 2>&1; then
    ok "candidatos montados íntegros"
  else
    bad "candidatos montados íntegros" "árbol o marcador inválido; ejecutar ENTORNO=$ENTORNO scripts/addons.sh status"
  fi

  # --- Selección ejecutada ---
  # El inventario de inicio prueba qué commits cargó el proceso, no solo qué hay hoy en el host.
  local startup current drift
  if ! corriendo odoo; then
    omitir "selección cargada coincide con candidatos" "$(motivo odoo)"
  else
    startup=$(contexto_compose exec -T odoo cat /tmp/odoo-addons-startup.json 2>/dev/null || true)
    current=$(CANDIDATE_LOCK_HELD=1 "$runtime_script" inventory 2>/dev/null || true)
    drift=$(python3 - "$startup" "$current" <<'PY' 2>/dev/null || true
import json
import sys

try:
    startup, current = (json.loads(value) for value in sys.argv[1:])
except (json.JSONDecodeError, TypeError):
    print("inventario ausente o inválido")
    raise SystemExit
if startup != current:
    print("los commits cargados difieren de los candidatos publicados")
PY
    )
    if [ -z "$drift" ]; then
      ok "selección cargada coincide con candidatos"
    else
      bad "selección cargada coincide con candidatos" "$drift; ejecutar ENTORNO=$ENTORNO make odoo-restart"
    fi
  fi

  # --- Módulos instalados disponibles ---
  # Informa divergencias sin actualizar la lista ni modificar la base.
  local disponibles instalados ausentes
  if ! corriendo odoo; then
    omitir "módulos instalados conservan su código" "$(motivo odoo)"
  else
    disponibles=$(contexto_compose exec -T odoo sh -c \
      "find /usr/lib/python3/dist-packages/odoo/addons /opt/odoo/custom /opt/odoo/enterprise -name __manifest__.py -type f -printf '%h\\n' 2>/dev/null | sed 's#.*/##' | sort -u" 2>/dev/null || true)
    instalados=$(contexto_compose exec -T postgres psql -U odoo -d odoo -Atc \
      "SELECT name FROM ir_module_module WHERE state = 'installed' ORDER BY name" 2>/dev/null || true)
    ausentes=$(comm -23 <(printf '%s\n' "$instalados" | sed '/^$/d' | sort -u) \
      <(printf '%s\n' "$disponibles" | sed '/^$/d' | sort -u))
    if [ -z "$ausentes" ]; then
      ok "módulos instalados conservan su código"
    else
      bad "módulos instalados conservan su código" "faltan: $(printf '%s' "$ausentes" | tr '\n' ' '); revisar y desinstalar manualmente antes de retirar el addon"
    fi
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
