# --- Componentes compuestos ---
# Encabezado de sección y marco de tabla para los targets del Makefile, sobre scripts/lib/ui.sh.

. scripts/lib/ui.sh

ui_section() { ui_title "━━━ $1 ━━━"; }

# --- Marco de tabla ---
# Envuelve en box-drawing lo que llega por stdin; mide el ancho sin color para no romper el padding.

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
