#!/usr/bin/env bash
# Prerrequisitos del sistema operativo, antes de levantar cualquier stack.
#
# No es un stack: no tiene contenedor ni ciclo de vida, así que no le corresponde
# una carpeta en stacks/. Vive acá, transversal, al lado del orquestador.
#
# Corre solo (scripts/verify-host.sh) o sourceado por scripts/verify-stacks.sh,
# que comparte los contadores y emite un único resumen.

. "$(dirname "${BASH_SOURCE[0]}")/lib/verify.sh"

# --- Rotación de logs según el sistema ---
# El chequeo del archivo del daemon solo aplica al Engine Linux.

verificar_rotacion_daemon() {
  local sistema="${1:-$(uname -s)}"
  if [ "$sistema" != "Linux" ]; then
    omitir "rotación de logs del daemon" "el chequeo de /etc/docker/daemon.json solo aplica a Linux"
  elif rotacion_aplicada; then
    ok "rotación de logs del daemon aplicada"
  else
    bad "rotación de logs del daemon aplicada" \
        "sin max-size en ${DAEMON_JSON:-/etc/docker/daemon.json} — correr: sudo make host-init"
  fi
}

v_host() {
  titulo "host"

  # --- Versión de Compose ---
  # include: exige 2.20; abajo de eso los entrypoints no resuelven y nada anda.

  local v mayor menor
  v=$(docker compose version --short 2>/dev/null)
  if [ -z "$v" ]; then
    bad "docker compose disponible" "no responde — ¿está el daemon corriendo?"
  else
    mayor=${v%%.*}; menor=$(printf '%s' "$v" | cut -d. -f2)
    if [ "$mayor" -gt 2 ] || { [ "$mayor" -eq 2 ] && [ "$menor" -ge 20 ]; }; then
      ok "docker compose $v (>= 2.20, exigido por include:)"
    else
      bad "docker compose >= 2.20" "es $v — include: no funciona"
    fi
  fi

  # --- Arranque automático ---
  # Sin esto un reboot deja el stack abajo y nadie se entera hasta que alguien entra.

  if command -v systemctl >/dev/null 2>&1; then
    expect "docker habilitado al boot" "enabled" systemctl is-enabled docker
  else
    omitir "docker habilitado al boot" "sin systemd"
  fi

  # --- Rotación de logs del daemon ---
  # Límite global que cubre contenedores presentes y futuros.

  verificar_rotacion_daemon

  # --- compose.env ---
  # Las claves vacías o ausentes se comparan con la plantilla versionada.

  local vacias faltantes plantilla
  vacias=$(grep -nE '^[A-Z0-9_]+=$' "$RUNTIME_ENV_FILE" 2>/dev/null | cut -d: -f2 | tr '\n' ' ')
  plantilla="$RUNTIME_DIR/compose.env.example"
  faltantes=$(claves_ausentes "$plantilla" "$RUNTIME_ENV_FILE")
  if [ ! -f "$RUNTIME_ENV_FILE" ]; then bad "runtime/$ENTORNO/compose.env presente" "copiar compose.env.example y completar los valores"
  elif [ -n "$vacias" ] || [ -n "$faltantes" ]; then
    bad "runtime/$ENTORNO/compose.env completo" "vacías: ${vacias:-ninguna} · ausentes: ${faltantes:-ninguna} (contra compose.env.example)"
  else ok "runtime/$ENTORNO/compose.env sin claves vacías ni ausentes"; fi

  # --- Identidad del stack ---
  # Un nombre vacío hace que Compose rechace la identidad del proyecto.

  local proyecto
  proyecto=$(contexto_compose config 2>/dev/null | sed -n 's/^name: //p' | head -1)
  if [ -z "$proyecto" ]; then
    bad "la composición resuelve" \
        "runtime/$ENTORNO/compose.yaml no resuelve — revisar runtime/$ENTORNO/compose.env"
  elif grep -qE '^COMPOSE_PROJECT_NAME=.+' "$RUNTIME_ENV_FILE" 2>/dev/null; then
    ok "identidad declarada en runtime/$ENTORNO/compose.env (proyecto: $proyecto)"
  else
    aviso "identidad declarada en runtime/$ENTORNO/compose.env" \
          "falta COMPOSE_PROJECT_NAME — Compose resolvió el proyecto como $proyecto"
  fi

  # --- Secrets ---
  # Delegado: scripts/secrets-perms.sh es el dueño único del mapa de GIDs.

  if scripts/secrets-perms.sh --check >/dev/null 2>&1; then
    ok "secrets con permisos, grupo y valor cargado"
  else
    bad "secrets con permisos, grupo y valor cargado" "correr: scripts/secrets-perms.sh --check"
  fi

  # --- Ningún contenedor en 0.0.0.0 ---
  # Transversal a propósito: el criterio de bind se viola de a un servicio, pero se
  # audita sobre el daemon entero — incluye contenedores que no son de este stack.

  local ps_out expuestos
  if ! ps_out=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null); then
    omitir "ningún contenedor publica en 0.0.0.0" "el daemon no responde"
  else
    expuestos=$(printf '%s\n' "$ps_out" | grep -E '0\.0\.0\.0:' | awk '{print $1}' | tr '\n' ' ')
    if [ -z "$expuestos" ]; then ok "ningún contenedor publica en 0.0.0.0"
    else bad "ningún contenedor publica en 0.0.0.0" "$expuestos"; fi
  fi
}

# --- Sourceado desde el orquestador o los tests ---
# Sin esto, importar el verificador correría la verificación entera y su exit code.

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

v_host
resumen
