# --- Componentes compuestos ---
# Encabezado de sección y marco de tabla para los targets del Makefile; se apoyan
# en scripts/lib/ui.sh, así que heredan su mismo criterio de TTY/NO_COLOR.

. scripts/lib/ui.sh

ui_section() { printf '\n%s━━━ %s ━━━%s\n' "$UI_BOLD" "$1" "$UI_RESET"; }

# --- Marco de tabla ---
# Envuelve en un box-drawing lo que llega por stdin, ya alineado por Docker;
# mide el ancho sobre el texto sin color para no romper el padding con ANSI.

ui_table_frame() {
  awk '
    { lines[NR] = $0
      plain = $0; gsub(/\033\[[0-9;]*m/, "", plain)
      if (length(plain) > maxlen) maxlen = length(plain)
    }
    END {
      top = "┌"; bot = "└"
      for (i = 0; i < maxlen + 2; i++) { top = top "─"; bot = bot "─" }
      print top "┐"
      for (i = 1; i <= NR; i++) {
        plain = lines[i]; gsub(/\033\[[0-9;]*m/, "", plain)
        printf "│ %s%*s │\n", lines[i], maxlen - length(plain), ""
      }
      print bot "┘"
    }'
}
