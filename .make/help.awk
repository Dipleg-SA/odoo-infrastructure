# --- Programa de 'help' ---
# Tres niveles: macro (Borde y red / Capa de datos / Aplicación / Observabilidad),
# micro (el stack puntual) y sus comandos — sexteto/trío sintetizado más los extras
# taggeados '# --- [STACK:nombre] Título ---' en el Makefile, todo junto por stack.
# Host (lo que no es de ningún stack puntual) va aparte, tal como aparece en el archivo.

BEGIN {
  FS = ":.*##"

  n_stacks = split(stacks, arr_stacks, " ")
  for (i = 1; i <= n_stacks; i++) is_sexteto[arr_stacks[i]] = 1

  n_oneshot = split(oneshot, arr_oneshot, " ")
  for (i = 1; i <= n_oneshot; i++) is_oneshot[arr_oneshot[i]] = 1

  macro_label["m_borde"] = "Borde y red"
  macro_label["m_datos"] = "Capa de datos"
  macro_label["m_app"]   = "Aplicación"
  macro_label["m_obs"]   = "Observabilidad"
  macro_var["m_borde"] = m_borde
  macro_var["m_datos"] = m_datos
  macro_var["m_app"]   = m_app
  macro_var["m_obs"]   = m_obs
  macro_order_n = split("m_borde m_datos m_app m_obs", macro_order, " ")

  mode = ""
}

# --- Recolección: un bloque '[STACK:nombre]' aporta sus targets al micro correspondiente ---
# No se imprime acá: se junta con el sexteto sintetizado de ese stack recién en END.

FILENAME == "Makefile" && /^# --- \[STACK:[a-zA-Z0-9_-]+\] .* ---$/ {
  match($0, /\[STACK:[a-zA-Z0-9_-]+\]/)
  cur_stack = substr($0, RSTART + 7, RLENGTH - 8)
  mode = "stack"
  next
}

# El marcador del sexteto no acumula nada — se sintetiza aparte, no se lee del archivo.

FILENAME == "Makefile" && /^# --- .*\[SEXTETO\].* ---$/ {
  mode = ""
  next
}

# Un micro dentro de Host: mismo nivel visual que el micro de un stack (indentado),
# pero sin lista de nombres contra la que emparejar — el título de la línea, tal
# cual, es el nombre que se muestra. sub() y no substr/RLENGTH: seguro con acentos.

FILENAME == "Makefile" && /^# --- \[HOST\] .* ---$/ {
  t = $0; sub(/^# --- \[HOST\] /, "", t); sub(/ ---$/, "", t)
  host_buf = host_buf sprintf("\n  \033[1m%s\033[0m\n", t)
  mode = "hostmicro"
  next
}

# Cualquier otro header es Host plano: se imprime tal cual, en el orden del archivo.

FILENAME == "Makefile" && /^# --- .* ---$/ {
  t = $0; sub(/^# --- /, "", t); sub(/ ---$/, "", t)
  host_buf = host_buf sprintf("\n\033[1m%s\033[0m\n", t)
  mode = "host"
  next
}

mode == "stack" && /^[a-zA-Z0-9_-]+:.*##/ {
  extra[cur_stack] = extra[cur_stack] sprintf("    \033[36m%-21s\033[0m %s\n", $1, substr($0, index($0, "##") + 3))
  next
}

mode == "hostmicro" && /^[a-zA-Z0-9_-]+:.*##/ {
  host_buf = host_buf sprintf("    \033[36m%-21s\033[0m %s\n", $1, substr($0, index($0, "##") + 3))
  next
}

mode == "host" && /^[a-zA-Z0-9_-]+:.*##/ {
  host_buf = host_buf sprintf("  \033[36m%-23s\033[0m %s\n", $1, substr($0, index($0, "##") + 3))
  next
}

# Red de seguridad: un target con '##' fuera de cualquier bloque no debería existir,
# pero si aparece no se pierde en silencio.

mode == "" && /^[a-zA-Z0-9_-]+:.*##/ {
  printf "  \033[36m%-23s\033[0m %s\n", $1, substr($0, index($0, "##") + 3)
}

# --- Salida ---
# Host primero, tal como quedó acumulado. Después cada macro, y dentro de cada una
# sus stacks en el orden declarado: sexteto (o trío) más los extras de ese stack.

END {
  printf "%s", host_buf

  for (mi = 1; mi <= macro_order_n; mi++) {
    key = macro_order[mi]
    printf "\n\033[1m\033[4m%s\033[0m\n", macro_label[key]
    ns = split(macro_var[key], members, " ")
    for (si = 1; si <= ns; si++) {
      s = members[si]
      printf "\n  \033[1m%s\033[0m\n", s
      if (s in is_sexteto) {
        printf "    \033[36m%-21s\033[0m Levanta %s\n", s "-up", s
        printf "    \033[36m%-21s\033[0m Baja %s\n", s "-down", s
        printf "    \033[36m%-21s\033[0m Reinicia %s, sin tocar el resto del stack\n", s "-restart", s
        printf "    \033[36m%-21s\033[0m Sigue los logs de %s\n", s "-logs", s
        printf "    \033[36m%-21s\033[0m Lista el contenedor de %s\n", s "-ps", s
        printf "    \033[36m%-21s\033[0m Verifica %s\n", s "-verify", s
      } else if (s in is_oneshot) {
        printf "    \033[36m%-21s\033[0m Sigue los logs de %s\n", s "-logs", s
        printf "    \033[36m%-21s\033[0m Lista el contenedor de %s\n", s "-ps", s
        printf "    \033[36m%-21s\033[0m Verifica %s\n", s "-verify", s
      }
      if (s in extra) printf "%s", extra[s]
    }
  }
}
