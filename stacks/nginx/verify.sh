#!/usr/bin/env bash
# Qué se espera del stack nginx. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.
#
# Corre solo (stacks/nginx/verify.sh) o sourceado por scripts/verify-stacks.sh,
# que comparte los contadores y emite un único resumen.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_nginx() {
  titulo "nginx"

  sano nginx

  # --- Config real, no plantilla ---
  # server-tls.conf es un archivo editado a mano: si quedó el placeholder de su
  # .example sin reemplazar, nginx levanta igual con un server_name inútil.

  if corriendo nginx; then
    vacio "sin el placeholder de server-tls.conf.example sin reemplazar" \
      docker compose exec -T nginx grep -r TU_DOMINIO /etc/nginx/conf.d/

    if modo_plain; then
      omitir "server_name es el hostname público" "modo plain: el server_name es el catch-all, no hay hostname que servir"
    elif [ -n "$PUBLIC_HOSTNAME" ]; then
      expect "server_name es el hostname público" "$PUBLIC_HOSTNAME" \
        docker compose exec -T nginx grep -h server_name /etc/nginx/conf.d/default.conf
    else
      omitir "server_name es el hostname público" "falta PUBLIC_HOSTNAME en .env"
    fi
  else
    omitir "sin el placeholder de server-tls.conf.example sin reemplazar" "$(motivo nginx)"
    omitir "server_name es el hostname público" "$(motivo nginx)"
  fi

  # --- Resolver dinámico ---
  # Sin resolver + proxy_pass por variable, nginx cachea la IP de Odoo al arrancar
  # y devuelve 502 en cuanto el contenedor se recrea, hasta que alguien lo recargue.

  if corriendo nginx; then
    vacio "proxy_pass va por variable, no por nombre fijo" \
      docker compose exec -T nginx grep -E 'proxy_pass http://odoo' /etc/nginx/conf.d/odoo.locations
    expect "resolver de Docker declarado" "127.0.0.11" \
      docker compose exec -T nginx grep -h resolver /etc/nginx/conf.d/00-http.conf
  else
    omitir "proxy_pass va por variable, no por nombre fijo" "$(motivo nginx)"
    omitir "resolver de Docker declarado" "$(motivo nginx)"
  fi

  # --- Las rutas de Odoo ---
  # Las tres: raíz, websocket al worker gevent, y el login con rate-limit. Se
  # cuentan sobre la config que nginx está sirviendo de verdad, no sobre el .example.

  local rutas
  if corriendo nginx; then
    rutas=$(docker compose exec -T nginx grep -c '^location' /etc/nginx/conf.d/odoo.locations 2>/dev/null | tr -d '\r ')
    if [ "${rutas:-0}" -ge 3 ]; then ok "las 3 rutas de Odoo en nginx"
    else bad "las 3 rutas de Odoo en nginx" "hay ${rutas:-0} — la config montada está incompleta"; fi
  else
    omitir "las 3 rutas de Odoo en nginx" "$(motivo nginx)"
  fi

  # --- La cadena nginx → Odoo ---
  # El único chequeo que recorre el camino de un request real, y el que prueba en
  # vivo que el resolver de arriba funciona: nginx resuelve odoo en cada request,
  # así que solo un request dice que resuelve. Es trabajo de nginx, aunque el
  # request salga desde el contenedor de Odoo — que es el único cliente que tiene.

  local via_proxy="la cadena nginx → Odoo responde"
  if ! corriendo nginx; then
    omitir "$via_proxy" "$(motivo nginx)"
  elif ! corriendo odoo; then
    omitir "$via_proxy" "$(motivo odoo)"
  elif modo_plain; then
    expect "$via_proxy" "200" docker compose exec -T odoo \
      curl -sS -o /dev/null -w '%{http_code}' http://nginx/web/login
  else
    # -k y Host: el certificado es del hostname público y acá se entra por el nombre
    # de servicio, que no es ninguno de sus SAN. Lo que se prueba es el ruteo, no el TLS.
    expect "$via_proxy" "200" docker compose exec -T odoo \
      curl -skS -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOSTNAME" https://nginx/web/login
  fi

  # --- Errores del proxy ---
  # "could not be resolved" es la contracara del resolver + proxy_pass por variable:
  # cada request que llega mientras Odoo no está deja uno, y el log no lo olvida nunca.

  log_limpio "nginx sin errores en el log" '\[error\]|\[emerg\]' 'could not be resolved' nginx

  # --- Binds ---
  # El esperado no se declara acá: lo lee bind_es de la composición resuelta, que
  # es la única que sabe qué publica ESTE entorno.

  bind_es nginx 80
  bind_es nginx 443
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_nginx
resumen
