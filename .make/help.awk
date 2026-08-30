# --- Programa de 'help' ---
# Agrupa por '# --- Título ---' y linkea cada '##' a su target; sintetiza el sexteto/trío.

BEGIN { FS = ":.*##" }

# Solo el Makefile principal aporta encabezados: .make/*.mk usa el mismo
# comentario '# --- Título ---' para sus propios bloques, no para el menú.
/^# --- .* ---$/ && FILENAME == "Makefile" {
  t = $0; sub(/^# --- /, "", t); sub(/ ---$/, "", t)
  sexteto = (t ~ /^\[SEXTETO\] /)
  if (sexteto) sub(/^\[SEXTETO\] /, "", t)
  printf "\n\033[1m%s\033[0m\n", t
  if (sexteto) {
    n = split(stacks, s, " ")
    for (i = 1; i <= n; i++) {
      printf "  \033[36m%-23s\033[0m  Levanta %s\n", s[i] "-up", s[i]
      printf "  \033[36m%-23s\033[0m  Baja %s\n", s[i] "-down", s[i]
      printf "  \033[36m%-23s\033[0m  Reinicia %s, sin tocar el resto del stack\n", s[i] "-restart", s[i]
      printf "  \033[36m%-23s\033[0m  Sigue los logs de %s\n", s[i] "-logs", s[i]
      printf "  \033[36m%-23s\033[0m  Lista el contenedor de %s\n", s[i] "-ps", s[i]
      printf "  \033[36m%-23s\033[0m  Verifica %s\n", s[i] "-verify", s[i]
    }
    m = split(oneshot, o, " ")
    for (i = 1; i <= m; i++) {
      printf "  \033[36m%-23s\033[0m  Sigue los logs de %s\n", o[i] "-logs", o[i]
      printf "  \033[36m%-23s\033[0m  Lista el contenedor de %s\n", o[i] "-ps", o[i]
      printf "  \033[36m%-23s\033[0m  Verifica %s\n", o[i] "-verify", o[i]
    }
  }
}

/^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-23s\033[0m %s\n", $1, substr($0, index($0, "##") + 2) }
