#!/usr/bin/env bash
# Contrato de promoción de código
# La promoción compara candidatos y edición, sin seleccionar imágenes históricas.
set -uo pipefail

cd "$(dirname "$0")/.."
. tests/lib.sh

titulo "promotion-verify.sh — sin estado de imágenes"
SCRIPT=$(cat scripts/promotion-verify.sh)
no_contiene "no consulta images.json" "images.json" "$SCRIPT"
no_contiene "no consulta la ranura Actual" "Actual" "$SCRIPT"
no_contiene "no conserva la ranura Anterior" "Anterior" "$SCRIPT"
no_contiene "no usa image-state" "image-state" "$SCRIPT"
contiene "sigue siendo un target Make" "promotion-verify:" "$(cat Makefile)"

resumen
