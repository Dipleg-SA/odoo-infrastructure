# --- Vocabulario visual ---
# Símbolos y color para todo el repo; se degrada a texto plano si la salida no es una
# terminal, o si NO_COLOR está seteada (no-color.org) aunque sí lo sea.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  UI_BOLD=$'\033[1m'; UI_UNDERLINE=$'\033[4m'; UI_CYAN=$'\033[36m'; UI_GREEN=$'\033[32m'
  UI_RED=$'\033[31m'; UI_YELLOW=$'\033[33m'; UI_DIM=$'\033[2m'; UI_RESET=$'\033[0m'
else
  UI_BOLD=''; UI_UNDERLINE=''; UI_CYAN=''; UI_GREEN=''; UI_RED=''; UI_YELLOW=''; UI_DIM=''; UI_RESET=''
fi

ui_title() { printf '\n%s%s%s\n' "$UI_BOLD" "$1" "$UI_RESET"; }
ui_start() { printf '%s▶%s %s\n' "$UI_CYAN" "$UI_RESET" "$1"; }
ui_ok()    { printf '%s✓%s %s\n' "$UI_GREEN" "$UI_RESET" "$1"; }
ui_skip()  { printf '%s–%s %s\n' "$UI_DIM" "$UI_RESET" "$1"; }

# --- Script de varios pasos ---
# Título destacado + pasos numerados, para scripts que narran un plan explícito.

ui_plan_start() { printf '\n%s▶%s %s%s%s\n\n' "$UI_CYAN" "$UI_RESET" "$UI_BOLD$UI_UNDERLINE" "$1" "$UI_RESET"; }
ui_step()       { printf '%s. %s\n\n' "$1" "$2"; }
ui_plan_end()   { echo; ui_step 2 "Finalizado."; }

ui_bad() {
  printf '%s✗%s %s\n' "$UI_RED" "$UI_RESET" "$1"
  if [ -n "${2:-}" ]; then printf '  %s%s%s\n' "$UI_DIM" "$2" "$UI_RESET"; fi
}

ui_warn() {
  printf '%s⚠%s %s\n' "$UI_YELLOW" "$UI_RESET" "$1"
  if [ -n "${2:-}" ]; then printf '  %s%s%s\n' "$UI_DIM" "$2" "$UI_RESET"; fi
}

# --- Cierre por exit code ---
# Corre el comando y marca ▶/✓/✗ según el exit code; el chequeo real es <capa>-verify.
# La duración solo se muestra a partir de 1s, para no ensuciar los comandos instantáneos.

ui_run() {
  local label="$1"; shift
  local inicio fin dur sufijo=""
  ui_start "$label"
  inicio=$(date +%s)
  "$@"; local ec=$?
  fin=$(date +%s); dur=$((fin - inicio))
  [ "$dur" -ge 1 ] && sufijo=" (${dur}s)"
  if [ "$ec" -eq 0 ]; then ui_ok "$label listo$sufijo"
  else ui_bad "$label falló$sufijo" "exit $ec"; fi
  return "$ec"
}

# --- Confirmación destructiva ---
# Pide escribir la palabra literal, no Y/N; devuelve 1 sin tocar nada si no coincide.

ui_confirm() {
  local palabra="$1" confirmacion
  read -r -p "Escribí '$palabra' para confirmar: " confirmacion
  [ "$confirmacion" = "$palabra" ] || { ui_skip "cancelado"; return 1; }
}
