#!/usr/bin/env bash
# Qué se espera del stack dnsmasq. Dueño único de estos valores: docs/runbooks/
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_dnsmasq() {
  titulo "dnsmasq"

  sano dnsmasq

  # --- Config real, no plantilla ---
  # dnsmasq.conf se edita a mano: con el placeholder sin reemplazar, dnsmasq
  # levanta igual y resuelve el hostname a una IP que no es la del servidor.

  sin_placeholder "dnsmasq.conf sin el placeholder de su .example" \
    stacks/dnsmasq/config/dnsmasq.conf 'TU_IP_LOCAL|TU_DOMINIO'

  # --- Quién le pregunta ---
  # El healthcheck le pregunta a dnsmasq: prueba que responde, no que alguien lo
  # consulte. Eso lo decide el DHCP del router, que este repositorio no toca, y
  # desde el servidor no hay forma de verificarlo — se comprueba con
  # `dig +short <hostname>` SIN @, corrido desde un equipo de la LAN.

  omitir "la LAN usa dnsmasq como resolver" \
    "lo decide el DHCP del router — verificar con dig desde un equipo de la red"
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_dnsmasq
resumen
