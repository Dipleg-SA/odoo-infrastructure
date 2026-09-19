#!/usr/bin/env bash
# Contrato arquitectónico de edición
# Comprueba que las decisiones de Community y Enterprise permanezcan documentadas.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

# Secciones acotadas
# Las aserciones se limitan al encabezado que posee cada contrato, no a cualquier coincidencia del documento.
seccion() {
  local archivo="$1" inicio="$2" fin="$3"
  awk -v inicio="$inicio" -v fin="$fin" \
    '$0 == inicio {activo=1; next} activo && $0 == fin {exit} activo {print}' "$archivo"
}

titulo "ARCHITECTURE.md — selección y transición de edición"

MODELO=$(seccion ARCHITECTURE.md '### Modelo vigente' '### Dos tipos de repositorio, una sola orquestación')
EDICION=$(seccion ARCHITECTURE.md '### Edición de Odoo' '## Capa de datos')
contiene "documenta la configuración plana" "ODOO_EDITION" "$MODELO"
contiene "documenta el catálogo vigente" "runtime/addons/catalogo.txt" "$MODELO"
contiene "documenta el receptor como stack" "addons-webhook" "$MODELO"
contiene "documenta el tag Community" "19.0-ce-" "$EDICION"
contiene "documenta el tag Enterprise" "19.0-ee-" "$EDICION"
contiene "documenta la frontera de transición" "frontera operativa" "$EDICION"
contiene "documenta recuperación mediante reconstrucción" "reconstru" "$EDICION"
no_contiene "README no usa entrypoints legacy" "envs/production.yaml" "$(cat README.md)"
no_contiene "README no usa catálogo legacy" "addons/addons.txt" "$(cat README.md)"
igual "no conserva el árbol legacy de addons" "0" "$([ ! -e addons ]; echo $?)"
DOCUMENTACION=$(seccion README.md '## Documentación' '## Cómo está pensado')
contiene "README explica registro en release" "release correspondiente" "$DOCUMENTACION"

titulo "Arquitectura — cuatro contratos de addons"

ADDONS_MODEL=$(seccion ARCHITECTURE.md \
  '### Gestión de addons: imagen, dependencias, candidatos y selección ejecutada' \
  '## Borde y red')
contiene "la imagen conserva Odoo y dependencias" "La imagen Odoo contiene" "$ADDONS_MODEL"
contiene "los candidatos se montan por entorno" 'runtime/<entorno>/addons/{custom,enterprise}' "$ADDONS_MODEL"
contiene "la recreación es explícita" 'up -d --force-recreate' "$ADDONS_MODEL"
contiene "la selección cargada queda registrada" '/tmp/odoo-addons-startup.json' "$ADDONS_MODEL"
contiene "la base participa de la identidad" 'odoo_base' "$ADDONS_MODEL"
no_contiene "no vuelve a describir addons copiados en la imagen" \
  'los copia a la imagen Odoo' "$ADDONS_MODEL"
no_contiene "no vuelve a describir una imagen como código ejecutado" \
  'no monta código de addons desde el host' "$ADDONS_MODEL"
igual "no prescribe docker compose restart para aplicar candidatos" "0" \
  "$(grep -Eiv 'no se usa|nunca' ARCHITECTURE.md | grep -c 'docker compose restart' || true)"
contiene "PRINCIPLES separa imagen y código" "Separá la imagen del código montado" \
  "$(cat PRINCIPLES.md)"
contiene "PRINCIPLES exige procedencia de arranque" "qué commits y árboles cargó Odoo" \
  "$(cat PRINCIPLES.md)"

titulo "Runbooks — orden de levantamiento por stacks"

orden_runbook() {
  local archivo="$1" edge postgres odoo backup monitoring
  edge=$(grep -n '^### 1\. Edge$' "$archivo" | head -1 | cut -d: -f1)
  postgres=$(grep -n '^### 2\. PostgreSQL' "$archivo" | head -1 | cut -d: -f1)
  odoo=$(grep -n '^### 3\. Odoo$' "$archivo" | head -1 | cut -d: -f1)
  backup=$(grep -n '^### 4\. Backup$' "$archivo" | head -1 | cut -d: -f1)
  monitoring=$(grep -n '^### 5\. Monitoring$' "$archivo" | head -1 | cut -d: -f1)
  [ -n "$edge" ] && [ -n "$postgres" ] && [ -n "$odoo" ] && [ -n "$backup" ] && [ -n "$monitoring" ] \
    && [ "$edge" -lt "$postgres" ] && [ "$postgres" -lt "$odoo" ] \
    && [ "$odoo" -lt "$backup" ] && [ "$backup" -lt "$monitoring" ]
}

for entorno in desarrollo staging produccion; do
  runbook="docs/entorno/levantar-$entorno.md"
  igual "$entorno declara el orden Edge/PostgreSQL/Odoo/Backup/Monitoring" "0" \
    "$(orden_runbook "$runbook"; echo $?)"
  postgres_line=$(grep -n 'make postgres-verify' "$runbook" | head -1 | cut -d: -f1)
  odoo_line=$(grep -n 'make odoo-up' "$runbook" | head -1 | cut -d: -f1)
  igual "$entorno verifica PostgreSQL antes de Odoo" "0" \
    "$([ -n "$postgres_line" ] && [ -n "$odoo_line" ] && [ "$postgres_line" -lt "$odoo_line" ]; echo $?)"
  no_contiene "$entorno no usa promoción de imagen" "apply-image" "$(cat "$runbook")"
  no_contiene "$entorno no usa rollback de imagen" "rollback-image" "$(cat "$runbook")"
done

no_contiene "desarrollo declara Edge ausente" "cloudflared-up" "$(cat docs/entorno/levantar-desarrollo.md)"
no_contiene "desarrollo declara Backup ausente como target" "backup-up" "$(cat docs/entorno/levantar-desarrollo.md)"
no_contiene "staging declara DNS ausente" "dnsmasq-up" "$(cat docs/entorno/levantar-staging.md)"
no_contiene "staging declara Monitoring ausente como target" "prometheus-up" "$(cat docs/entorno/levantar-staging.md)"
contiene "producción levanta Backup" "make backup-up" "$(cat docs/entorno/levantar-produccion.md)"
contiene "producción levanta Monitoring" "make prometheus-up" "$(cat docs/entorno/levantar-produccion.md)"

titulo "Documentación — selector único y recuperación explícita"

for documento in \
  docs/modulos/construir-y-aplicar-imagen.md \
  docs/modulos/validar-promocion.md \
  docs/modulos/gestionar-modulo.md \
  docs/modulos/gestionar-fork.md \
  docs/modulos/gestionar-ramas-staging.md \
  docs/modulos/gestionar-enterprise.md \
  docs/modulos/especificacion-gestion-addons.md \
  docs/operacion/operar-backups.md \
  docs/operacion/operar-odoo.md \
  docs/operacion/operar-webhook-addons.md \
  docs/backup-restore/migrar-deployment-externo.md; do
  no_contiene "$documento no conserva apply-image" "apply-image" "$(cat "$documento")"
  no_contiene "$documento no conserva image-state" "image-state" "$(cat "$documento")"
  no_contiene "$documento no conserva images.json operativo" "images.json" "$(cat "$documento")"
done

contiene "construcción documenta el selector" "ODOO_IMAGE" "$(cat docs/modulos/construir-y-aplicar-imagen.md)"
contiene "promoción documenta el build productivo" "promotion-verify" "$(cat docs/modulos/validar-promocion.md)"
contiene "backup documenta la reconstrucción" "reconstruye" "$(cat docs/operacion/operar-backups.md)"
contiene "webhook documenta el candidato" "candidato" "$(cat docs/operacion/operar-webhook-addons.md)"

titulo "Spec-Flow — estado, estructura y backlog"

for artefacto in \
  .specs/001-gestion-addons-inmutables/spec.md \
  .specs/001-gestion-addons-inmutables/plan.md \
  .specs/001-gestion-addons-inmutables/tasks.md \
  .specs/002-edicion-community-enterprise/spec.md \
  .specs/002-edicion-community-enterprise/plan.md \
  .specs/002-edicion-community-enterprise/tasks.md; do
  estado=$(awk -F '|' 'NR == 5 {gsub(/[[:space:]]/, "", $6); print $6}' "$artefacto")
  igual "$artefacto declara estado convergido" "Converged" "$estado"
  no_contiene "$artefacto no conserva encabezados en inglés" "## Phase" "$(cat "$artefacto")"
  no_contiene "$artefacto no conserva título Spec/Tasks" "# Spec:" "$(cat "$artefacto")"
  no_contiene "$artefacto no conserva título Tasks" "# Tasks:" "$(cat "$artefacto")"
done

contiene "SPEC-001 identifica contexto histórico" "Estado y contexto" "$(cat .specs/001-gestion-addons-inmutables/spec.md)"
contiene "SPEC-001 documenta rutas vigentes" "runtime/<entorno>/" "$(cat .specs/001-gestion-addons-inmutables/plan.md)"
contiene "SPEC-002 identifica contexto histórico" "Estado y contexto" "$(cat .specs/002-edicion-community-enterprise/spec.md)"
contiene "SPEC-002 documenta configuración plana" "runtime/<entorno>/compose.env" "$(cat .specs/002-edicion-community-enterprise/plan.md)"

BACKLOG=$(cat .specs/backlog.md)
contiene "backlog presente" "# Backlog" "$BACKLOG"
igual "backlog sin ítems abiertos" "" "$(printf '%s\n' "$BACKLOG" | rg '^- \[ \] B[0-9]{3}\b' || true)"
sale_con "backlog no está ignorado" 1 git check-ignore -q -- .specs/backlog.md

resumen
