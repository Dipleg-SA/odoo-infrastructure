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
contiene "documenta el rollback condicionado" "rollback" "$EDICION"
no_contiene "README no usa entrypoints legacy" "envs/production.yaml" "$(cat README.md)"
no_contiene "README no usa catálogo legacy" "addons/addons.txt" "$(cat README.md)"
DOCUMENTACION=$(seccion README.md '## Documentación' '## Cómo está pensado')
contiene "README explica registro en release" "release correspondiente" "$DOCUMENTACION"

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
