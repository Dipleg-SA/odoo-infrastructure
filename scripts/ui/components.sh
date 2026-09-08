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

# --- Tabla de 'docker compose ps' ---
# Lee NAME/STATUS/PORTS separados por TAB (--format, sin 'table': sin padding propio) y
# arma las columnas acá. El color se aplica al STATUS ya aislado en su propio campo —
# nunca a la línea completa— porque STATUS no es la última columna cuando hay PORTS
# al lado, y anclar el color a fin de línea nunca matchea ahí.

ui_ps_table() {
  awk -F'\t' -v green="$UI_GREEN" -v red="$UI_RED" -v yellow="$UI_YELLOW" -v reset="$UI_RESET" '
    BEGIN { name_w = 4; status_w = 6 }
    {
      name[NR] = $1; status_raw[NR] = $2; ports[NR] = $3
      s = $2
      if (s ~ /^Up.*\(healthy\)$/)              { s = green s reset }
      else if (s ~ /^Up.*\(unhealthy\)$/)       { s = red s reset }
      else if (s ~ /^(Exited|Restarting|Dead)/) { s = red s reset }
      else if (s ~ /^(Up|Created|Paused)/)      { s = yellow s reset }
      status[NR] = s
      if (length($1) > name_w) name_w = length($1)
      if (length($2) > status_w) status_w = length($2)
    }
    END {
      printf "%-*s  %-*s  %s\n", name_w, "NAME", status_w, "STATUS", "PORTS"
      for (i = 1; i <= NR; i++) {
        printf "%-*s  %s", name_w, name[i], status[i]
        for (j = 0; j < status_w - length(status_raw[i]); j++) printf " "
        printf "  %s\n", ports[i]
      }
    }' | ui_table_frame
}
