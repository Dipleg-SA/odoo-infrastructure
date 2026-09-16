# Composición con perfiles fusionados
# Conserva COMPOSE_PROFILES del runtime y usa el contexto centralizado.

. "$(dirname "${BASH_SOURCE[0]}")/contexto.sh"

perfiles_fusionados() { echo "cert,restore${COMPOSE_PROFILES:+,$COMPOSE_PROFILES}"; }

configuracion()     { COMPOSE_PROFILES="$(perfiles_fusionados)" contexto_compose config 2>/dev/null; }
servicios_activos() { COMPOSE_PROFILES="$(perfiles_fusionados)" contexto_compose config --services 2>/dev/null; }
