#!/usr/bin/env bash
# Qué se espera del stack odoo. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.
#
# Corre solo (stacks/odoo/verify.sh) o sourceado por scripts/verify-stacks.sh,
# que comparte los contadores y emite un único resumen.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

ODOO_CONF=stacks/odoo/config/odoo.conf
ODOO_DOCKERFILE=stacks/odoo/image/Dockerfile
ODOO_ENTRYPOINT=stacks/odoo/image/entrypoint.sh

v_odoo() {
  titulo "odoo"

  sano odoo

  log_limpio "odoo sin errores de permisos" 'permission denied' "" odoo

  # --- Placeholder de odoo.conf sin reemplazar ---
  # smtp_server no llega por .env: si quedó el placeholder de su .example, Odoo
  # intenta mandar por un host que no existe en vez de quedar sin SMTP.
  #
  # Solo donde el valor se usa: los entornos que fuerzan ODOO_DISABLE_SMTP vacían
  # smtp_server en el entrypoint, así que ahí el placeholder es lo esperado.

  if ! smtp_activo; then
    omitir "odoo.conf sin el placeholder de su .example" \
      "este stack fuerza ODOO_DISABLE_SMTP — el smtp_server de odoo.conf no se usa"
  else
    sin_placeholder "odoo.conf sin el placeholder de su .example" \
      "$ODOO_CONF" 'TU_SMTP_HOST|TU_SMTP_PORT|TU_SMTP_USER'
  fi

  expect "odoo sirve en :8069" "200" docker compose exec -T odoo \
    curl -sS -o /dev/null -w '%{http_code}' http://localhost:8069/web/login

  # --- Árbol de addons ---
  # Llegan por bind-mount: su presencia ya no la garantiza la imagen.

  local estado sucios faltan
  estado=$(scripts/addons.sh status 2>/dev/null | grep -E '^(enterprise|custom-addons|oca|third-party)[[:space:]]')
  sucios=$(printf '%s\n' "$estado" | awk '$NF=="sucio" {print $2}' | tr '\n' ' ')
  faltan=$(printf '%s\n' "$estado" | grep 'sin worktree' | awk '{print $2}' | tr '\n' ' ')
  if [ -z "$estado" ]; then
    bad "worktrees del checkout presentes" "árbol vacío — correr make addons-sync"
  elif [ -n "$faltan" ]; then
    bad "worktrees del checkout presentes" "sin clonar: $faltan — correr make addons-sync"
  elif [ -n "$sucios" ]; then
    bad "worktrees del checkout limpios" "sucios: $sucios — addons.sh no actualiza un worktree con cambios"
  else
    ok "worktrees del checkout presentes y limpios"
  fi

  # --- Módulos server-wide presentes en el árbol ---
  # Odoo NO falla si uno no existe: loguea el error y sigue. El síntoma aparece
  # lejos de la causa — el bus deja de actualizar en tiempo real, por ejemplo.

  local swm mod hallado
  swm=$(sed -n 's/^server_wide_modules[[:space:]]*=[[:space:]]*\(.*\)/\1/p' "$ODOO_CONF" 2>/dev/null | tr -d ' ' | tr ',' '\n')
  while read -r mod; do
    [ -n "$mod" ] || continue
    case "$mod" in base|web) continue ;; esac
    hallado=$(find addons -mindepth 3 -maxdepth 3 -type d -name "$mod" 2>/dev/null | head -1)
    if [ -n "$hallado" ]; then
      ok "módulo server-wide '$mod' presente en el árbol"
    else
      bad "módulo server-wide '$mod' presente en el árbol" \
          "no está en addons/ — Odoo arranca igual y falla en silencio"
    fi
  done <<< "$swm"

  # --- Rama de addons contra la versión de la imagen ---
  # Clonar ramas de una versión y montarlas en un Odoo de otra rompe de formas
  # raras. Prefijo y no igualdad: 19.0-stag es coherente con la imagen 19.0, y
  # 18.0 no lo es. La versión vive solo en el Dockerfile; ADDONS_BRANCH la hereda.

  local ver_img rama
  ver_img=$(sed -n 's/^FROM odoo:\([0-9.]*\).*/\1/p' "$ODOO_DOCKERFILE" 2>/dev/null | head -1)
  rama="${ADDONS_BRANCH:-$ver_img}"
  if [ -z "$ver_img" ]; then
    aviso "ADDONS_BRANCH coherente con la imagen" "no se pudo leer el tag del Dockerfile"
  else
    case "$rama" in
      "$ver_img"|"$ver_img"-*)
        ok "ADDONS_BRANCH ($rama) coherente con la imagen ($ver_img)" ;;
      # Una rama de feature no lleva la versión en el nombre, así que no hay nada
      # que cruzar: se avisa en vez de fallar, y el operador es quien sabe de dónde salió.
      [!0-9]*)
        aviso "ADDONS_BRANCH coherente con la imagen" \
              "'$rama' no declara versión — nada garantiza que sea de la $ver_img" ;;
      *)
        bad "ADDONS_BRANCH coherente con la imagen" \
            "ADDONS_BRANCH=$rama contra imagen $ver_img" ;;
    esac
  fi

  # --- Categorías de addons ---
  # La lista vive en dos archivos: addons.sh valida contra ella y el entrypoint
  # arma el addons_path recorriéndola. Si divergen, los módulos de la categoría
  # que falta se clonan y nunca se cargan — sin error, solo no aparecen.

  local cats_sync cats_path
  cats_sync=$(sed -n 's/^[[:space:]]*\([a-z|-]*\)) return 0 ;;/\1/p' scripts/addons.sh | tr '|' '\n' | sort | tr '\n' ' ')
  cats_path=$(sed -n 's/^for category in \(.*\); do/\1/p' "$ODOO_ENTRYPOINT" 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ')
  if [ -z "$cats_sync" ] || [ -z "$cats_path" ]; then
    aviso "categorías coherentes entre sync y addons_path" "no se pudieron leer las listas"
  elif [ "$cats_sync" = "$cats_path" ]; then
    ok "categorías coherentes entre sync y addons_path"
  else
    bad "categorías coherentes entre sync y addons_path" \
        "addons.sh: [$cats_sync] · entrypoint: [$cats_path]"
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
