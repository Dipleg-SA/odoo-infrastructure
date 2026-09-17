#!/usr/bin/env bash
# Qué se espera del stack nginx. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_nginx() {
  titulo "nginx"

  sano nginx

  # --- Config real, no plantilla ---
  # La configuración montada no debe conservar el placeholder TU_DOMINIO.

  if corriendo nginx; then
    vacio "sin el placeholder de server-tls.conf.example sin reemplazar" \
      contexto_compose exec -T nginx sh -c \
        "grep -rv '^[[:space:]]*#' /etc/nginx/conf.d/ | grep TU_DOMINIO"

    if modo_plain; then
      omitir "server_name es el hostname público" "modo plain: el server_name es el catch-all, no hay hostname que servir"
    elif [ -n "$PUBLIC_HOSTNAME" ]; then
      expect "server_name es el hostname público" "$PUBLIC_HOSTNAME" \
        contexto_compose exec -T nginx grep -h server_name /etc/nginx/conf.d/default.conf
    else
      omitir "server_name es el hostname público" "falta PUBLIC_HOSTNAME en runtime/$ENTORNO/compose.env"
    fi
  else
    omitir "sin el placeholder de server-tls.conf.example sin reemplazar" "$(motivo nginx)"
    omitir "server_name es el hostname público" "$(motivo nginx)"
  fi

  # --- Resolver dinámico ---
  # El resolver dinámico evita cachear una IP vieja de Odoo después de recrearlo.

  if corriendo nginx; then
    vacio "proxy_pass va por variable, no por nombre fijo" \
      contexto_compose exec -T nginx grep -E 'proxy_pass http://odoo' /etc/nginx/conf.d/odoo.locations
    expect "resolver de Docker declarado" "127.0.0.11" \
      contexto_compose exec -T nginx grep -h resolver /etc/nginx/conf.d/00-http.conf
  else
    omitir "proxy_pass va por variable, no por nombre fijo" "$(motivo nginx)"
    omitir "resolver de Docker declarado" "$(motivo nginx)"
  fi

  # --- Las rutas de Odoo ---
  # La configuración activa debe contener raíz, websocket y login con rate-limit.

  local rutas
  if corriendo nginx; then
    rutas=$(contexto_compose exec -T nginx grep -c '^location' /etc/nginx/conf.d/odoo.locations 2>/dev/null | tr -d '\r ')
    if [ "${rutas:-0}" -ge 3 ]; then ok "las 3 rutas de Odoo en nginx"
    else bad "las 3 rutas de Odoo en nginx" "hay ${rutas:-0} — la config montada está incompleta"; fi
  else
    omitir "las 3 rutas de Odoo en nginx" "$(motivo nginx)"
  fi

  # --- La cadena nginx → Odoo ---
  # Un request real desde Odoo confirma ruteo, resolución y respuesta del proxy.

  local via_proxy="la cadena nginx → Odoo responde"
  if ! corriendo nginx; then
    omitir "$via_proxy" "$(motivo nginx)"
  elif ! corriendo odoo; then
    omitir "$via_proxy" "$(motivo odoo)"
  elif modo_plain; then
    expect "$via_proxy" "200" contexto_compose exec -T odoo \
      curl -sS -o /dev/null -w '%{http_code}' http://nginx/web/login
  else
    # -k y Host prueban el ruteo del hostname público sin exigir el SAN del servicio.
    # La prueba valida el proxy, no la cadena de confianza TLS.
    expect "$via_proxy" "200" contexto_compose exec -T odoo \
      curl -skS -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOSTNAME" https://nginx/web/login
  fi

  # --- Errores del proxy ---
  # El log no debe conservar errores de resolución ni emergencias del proxy.

  log_limpio "nginx sin errores en el log" '\[error\]|\[emerg\]' 'could not be resolved' nginx

  # --- Binds ---
  # bind_es obtiene la IP publicada directamente de la composición del entorno.

  bind_es nginx 80
  bind_es nginx 443
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_nginx
resumen
