# --- Composición, con los perfiles fusionados ---
# Comparten esto verify.sh, secrets-init.sh y config-init.sh: los tres necesitan
# preguntarle a `docker compose config` qué trae ESTE checkout, y los tres pisarían
# el mismo error si lo repitieran cada uno a su manera.
#
# Un --profile explícito REEMPLAZA a COMPOSE_PROFILES, no se suma — medido: listar
# con --profile cert --profile restore descarta el 'lan' que trajo el .env del
# operador. La fusión va en la VARIABLE para no perder lo que ya traía.

perfiles_fusionados() { echo "cert,restore${COMPOSE_PROFILES:+,$COMPOSE_PROFILES}"; }

configuracion()    { COMPOSE_PROFILES="$(perfiles_fusionados)" docker compose config 2>/dev/null; }
servicios_activos() { COMPOSE_PROFILES="$(perfiles_fusionados)" docker compose config --services 2>/dev/null; }
