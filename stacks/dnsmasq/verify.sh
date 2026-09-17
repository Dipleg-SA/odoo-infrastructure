#!/usr/bin/env bash
# Qué se espera del stack dnsmasq. Dueño único de estos valores: el runbook
# nombra el comando, los valores viven acá.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/verify.sh"

v_dnsmasq() {
  titulo "dnsmasq"

  # --- Perfil LAN ---
  # Un perfil declarado pero inactivo no es un servicio sano ni un stack ausente.

  if perfil_inactivo dnsmasq lan; then
    omitir "dnsmasq" "perfil lan inactivo — activar COMPOSE_PROFILES=lan si corresponde"
    return
  fi

  sano dnsmasq

  # --- Config real, no plantilla ---
  # dnsmasq.conf no debe conservar TU_IP_LOCAL ni TU_DOMINIO.

  sin_placeholder "dnsmasq.conf sin el placeholder de su .example" \
    stacks/dnsmasq/config/dnsmasq.conf 'TU_IP_LOCAL|TU_DOMINIO'

  # --- Quién le pregunta ---
  # El uso por la LAN depende del DHCP externo y se verifica con dig sin @.

  omitir "la LAN usa dnsmasq como resolver" \
    "lo decide el DHCP del router — verificar con dig desde un equipo de la red"
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_dnsmasq
resumen
