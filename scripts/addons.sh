#!/usr/bin/env bash
# Candidatos de addons por runtime
# Sincroniza snapshots de ramas fijas desde un catálogo de repositorios de dominio.
set -euo pipefail
shopt -s nullglob

cd "$(dirname "$0")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
. scripts/lib/candidate-lock.sh
contexto_iniciar

if [ "${CANDIDATE_LOCK_HELD:-0}" != "1" ]; then
  candidate_lock_run "$ENTORNO" -- env CANDIDATE_LOCK_HELD=1 "$0" "$@"
  exit $?
fi

# Rutas y rama del entorno
# El catálogo y los clones se comparten; cada entorno recibe su propio candidato.
ROOT="$PWD"
ADDONS_ROOT="$ROOT/runtime/addons"
CATALOGO="$ADDONS_ROOT/catalogo.txt"
BARE_DIR="$ADDONS_ROOT/.repos"
CANDIDATE_ROOT="$ADDONS_ROOT/custom/$ENTORNO"
VERSION="$(contexto_odoo_version | head -1)"

if [ -z "$VERSION" ]; then
  printf 'addons.sh: no se pudo leer la línea de Odoo desde stacks/odoo/image/Dockerfile\n' >&2
  exit 1
fi

case "$ENTORNO" in
  desarrollo) RAMA="${VERSION}-dev" ;;
  staging) RAMA="${VERSION}-stag" ;;
  produccion) RAMA="$VERSION" ;;
esac

FAILED=0
DOMINIOS=()
URLS=()
DOMINIO_COUNT=0
BARE_RESULT=""

fail() { printf 'addons.sh: %s\n' "$1" >&2; FAILED=1; }
warn() { printf 'addons.sh: aviso: %s\n' "$1" >&2; }

# Checkout único de Enterprise
# Vive fuera del catálogo y solo se selecciona por un tag fechado de la línea.
ENTERPRISE_ROOT="$ADDONS_ROOT/enterprise"

enterprise_usage() {
  printf 'uso: %s enterprise <sync|status|validate> [URL] [TAG]\n' "$(basename "$0")" >&2
  printf 'o:   %s enterprise-sync [URL] [TAG]\n' "$(basename "$0")" >&2
}

enterprise_url_validar() {
  local url="$1"
  case "$url" in
    https://*|ssh://*|git@*:*|file://*|/*|./*|../*) ;;
    *) fail "URL de Enterprise no admitida: $url"; return 1 ;;
  esac
  case "$url" in
    *\?*|*\#*) fail "la URL de Enterprise no puede incluir query ni fragmento: $url"; return 1 ;;
    https://*@*|ssh://*@*)
      [[ "$url" == ssh://git@* ]] || { fail "la URL de Enterprise no puede incluir credenciales: $url"; return 1; }
      ;;
  esac
}

enterprise_tag_validar() {
  local tag="$1"
  if [[ ! "$tag" =~ ^${VERSION}-ee-[0-9]{4}-[0-9]{2}-[0-9]{2}([-.][A-Za-z0-9._-]+)?$ ]]; then
    fail "el tag de Enterprise debe seguir ${VERSION}-ee-YYYY-MM-DD"
    return 1
  fi
}

enterprise_checkout_validar() {
  local url="$1" tag="$2" remoto commit tag_commit estado nuevo=0
  if [ -L "$ENTERPRISE_ROOT" ]; then
    fail "runtime/addons/enterprise no puede ser un enlace simbólico"
    return 1
  fi
  if [ ! -d "$ENTERPRISE_ROOT/.git" ]; then
    mkdir -p "$ADDONS_ROOT"
    if ! git clone --no-checkout -- "$url" "$ENTERPRISE_ROOT"; then
      rm -rf "$ENTERPRISE_ROOT"
      fail "no se pudo clonar Enterprise"
      return 1
    fi
    nuevo=1
  fi
  remoto=$(git -C "$ENTERPRISE_ROOT" remote get-url origin 2>/dev/null) || {
    fail "runtime/addons/enterprise no tiene un remoto origin"; return 1;
  }
  if [ "$remoto" != "$url" ]; then
    fail "la URL de Enterprise difiere del remoto origin; revisar manualmente"
    return 1
  fi
  estado=$(git -C "$ENTERPRISE_ROOT" status --porcelain 2>/dev/null || true)
  if [ "$nuevo" -eq 0 ] && [ -n "$estado" ]; then
    fail "el checkout de Enterprise tiene cambios locales; no se puede seleccionar el tag"
    return 1
  fi
  if ! git -C "$ENTERPRISE_ROOT" fetch --no-tags origin \
      "refs/tags/$tag:refs/tags/$tag" 2>&1; then
    fail "no se pudo resolver el tag inmutable de Enterprise: $tag"
    return 1
  fi
  tag_commit=$(git -C "$ENTERPRISE_ROOT" rev-parse --verify "$tag^{commit}" 2>/dev/null) || {
    fail "el tag de Enterprise no apunta a un commit: $tag"; return 1;
  }
  [ "$(git -C "$ENTERPRISE_ROOT" cat-file -t "refs/tags/$tag" 2>/dev/null || true)" = tag ] || {
    fail "el tag de Enterprise debe ser anotado e inmutable: $tag"; return 1;
  }
  git -C "$ENTERPRISE_ROOT" show-ref --tags --verify "refs/tags/$tag" >/dev/null 2>&1 || {
    fail "el tag de Enterprise no existe como referencia de tag: $tag"; return 1;
  }
  if ! git -C "$ENTERPRISE_ROOT" checkout --detach --force "$tag" >/dev/null 2>&1; then
    fail "no se pudo seleccionar el tag de Enterprise: $tag"
    return 1
  fi
  if [ -n "$(git -C "$ENTERPRISE_ROOT" status --porcelain 2>/dev/null)" ]; then
    fail "el checkout de Enterprise quedó sucio después de seleccionar el tag"
    return 1
  fi
  ui_ok "Enterprise seleccionado — $tag ($tag_commit)"
}

enterprise_sync() {
  local url="${1:-${ENTERPRISE_REPOSITORY:-}}" tag="${2:-${ENTERPRISE_TAG:-}}"
  if [ -z "$url" ] || [ -z "$tag" ]; then
    enterprise_usage
    return 2
  fi
  enterprise_url_validar "$url" || return 1
  enterprise_tag_validar "$tag" || return 1
  enterprise_checkout_validar "$url" "$tag"
}

enterprise_validate() {
  local tag="${1:-${ENTERPRISE_TAG:-}}" commit expected
  if [ -z "$tag" ]; then
    enterprise_usage
    return 2
  fi
  enterprise_tag_validar "$tag" || return 1
  [ -d "$ENTERPRISE_ROOT/.git" ] || { fail "falta runtime/addons/enterprise; ejecutar enterprise sync"; return 1; }
  commit=$(git -C "$ENTERPRISE_ROOT" rev-parse --verify HEAD 2>/dev/null) || { fail "Enterprise no tiene HEAD resoluble"; return 1; }
  expected=$(git -C "$ENTERPRISE_ROOT" rev-parse --verify "$tag^{commit}" 2>/dev/null) || { fail "el tag de Enterprise no existe localmente: $tag"; return 1; }
  [ "$(git -C "$ENTERPRISE_ROOT" cat-file -t "refs/tags/$tag" 2>/dev/null || true)" = tag ] || { fail "el tag de Enterprise debe ser anotado e inmutable: $tag"; return 1; }
  [ "$commit" = "$expected" ] || { fail "Enterprise no está seleccionado en el tag $tag"; return 1; }
  [ -z "$(git -C "$ENTERPRISE_ROOT" status --porcelain 2>/dev/null)" ] || { fail "el checkout de Enterprise tiene cambios locales"; return 1; }
  printf 'enterprise: %s · commit: %s\n' "$tag" "$commit"
}

enterprise_status() {
  [ -d "$ENTERPRISE_ROOT/.git" ] || { printf 'enterprise: sin checkout\n'; return 1; }
  local tag commit
  tag=$(git -C "$ENTERPRISE_ROOT" describe --tags --exact-match HEAD 2>/dev/null || true)
  commit=$(git -C "$ENTERPRISE_ROOT" rev-parse --verify HEAD 2>/dev/null || true)
  printf 'enterprise: %s · commit: %s\n' "${tag:--}" "${commit:--}"
}

cmd_enterprise() {
  local accion="${1:-}"; shift || true
  case "$accion" in
    sync) enterprise_sync "$@" ;;
    validate) enterprise_validate "$@" ;;
    status) enterprise_status "$@" ;;
    *) enterprise_usage; return 2 ;;
  esac
}

# Catálogo de dominio
# Cada línea contiene una sola URL Git; el nombre se deriva del último segmento.
require_catalogo() {
  if [ ! -f "$CATALOGO" ]; then
    printf 'addons.sh: no existe runtime/addons/catalogo.txt\n' >&2
    printf 'addons.sh: copiar runtime/addons/catalogo.txt.example y completar las URL de repositorios\n' >&2
    exit 1
  fi
}

nombre_repositorio() {
  local url="$1" ruta
  ruta="${url%/}"
  ruta="${ruta##*/}"
  ruta="${ruta%.git}"
  printf '%s' "$ruta"
}

catalogo_validar() {
  local linea url extra dominio formato_invalido=0 existente
  DOMINIOS=()
  URLS=()
  DOMINIO_COUNT=0

  while IFS= read -r linea || [ -n "$linea" ]; do
    linea="${linea#"${linea%%[![:space:]]*}"}"
    [ -z "$linea" ] && continue
    [[ "$linea" == \#* ]] && continue

    read -r url extra <<< "$linea"
    if [ -z "$url" ] || [ -n "${extra:-}" ]; then
      fail "cada línea de runtime/addons/catalogo.txt debe contener una sola URL Git"
      formato_invalido=1
      continue
    fi
    case "$url" in
      https://*|ssh://*|git@*:*|file://*|/*|./*|../*) ;;
      *)
        fail "URL Git no admitida en runtime/addons/catalogo.txt: $url"
        formato_invalido=1
        continue
        ;;
    esac
    case "$url" in
      *\?*|*\#*)
        fail "la URL Git no puede incluir query ni fragmento: $url"
        formato_invalido=1
        continue
        ;;
      https://*@*|ssh://*@*)
        [[ "$url" == ssh://git@* ]] || {
          fail "la URL Git no puede incluir credenciales: $url"
          formato_invalido=1
          continue
        }
        ;;
    esac

    dominio=$(nombre_repositorio "$url")
    if [[ ! "$dominio" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      fail "nombre de dominio inválido derivado de la URL: $url"
      formato_invalido=1
      continue
    fi
    if [ "$dominio" = enterprise ]; then
      fail "Enterprise se administra fuera de runtime/addons/catalogo.txt"
      formato_invalido=1
      continue
    fi
    for existente in "${DOMINIOS[@]-}"; do
      [ -n "$existente" ] || continue
      if [ "$existente" = "$dominio" ]; then
        fail "el catálogo repite el dominio '$dominio'"
        formato_invalido=1
        break
      fi
    done
    [ "$formato_invalido" -eq 0 ] || continue
    DOMINIOS+=("$dominio")
    URLS+=("$url")
    DOMINIO_COUNT=$((DOMINIO_COUNT + 1))
  done < "$CATALOGO"

  if [ "$formato_invalido" -ne 0 ]; then
    ui_bad "catálogo inválido" "no se clonó ni publicó ningún candidato" >&2
    return 1
  fi
}

# Clon bare compartido
# El refspec explícito permite consultar las ramas de entorno como origin/<rama>.
ensure_bare() {
  local url="$1" dominio="$2" bare="$BARE_DIR/$dominio.git" err remoto
  BARE_RESULT=""
  if [ ! -d "$bare" ]; then
    if ! err=$(git clone --bare -- "$url" "$bare" 2>&1); then
      fail "$dominio: clonado bare falló — $err"
      rm -rf "$bare"
      return 1
    fi
  fi
  if ! remoto=$(git -C "$bare" remote get-url origin 2>/dev/null); then
    fail "$dominio: $bare no es un clon bare con remoto origin"
    return 1
  fi
  if [ "$remoto" != "$url" ]; then
    fail "$dominio: la URL del catálogo difiere del clon bare; revisar o retirar $bare manualmente"
    return 1
  fi
  git -C "$bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  if ! err=$(git -C "$bare" fetch --prune origin 2>&1); then
    fail "$dominio: fetch de origin falló — $err"
    return 1
  fi
  BARE_RESULT="$bare"
}

# Publicación de candidato
# Exporta un commit completo y reemplaza el árbol solo después de extraerlo.
publicar_candidato() {
  local bare="$1" dominio="$2" commit="$3" candidato="$CANDIDATE_ROOT/$dominio"
  local temporal anterior="" padre="$CANDIDATE_ROOT" respaldo err
  mkdir -p "$padre"
  if ! temporal=$(mktemp -d "$padre/.${dominio}.XXXXXX"); then
    fail "$dominio: no se pudo crear el directorio temporal del candidato"
    return 1
  fi
  if ! git -C "$bare" archive --format=tar "$commit" | tar -xf - -C "$temporal"; then
    rm -rf "$temporal"
    fail "$dominio: no se pudo exportar el commit $commit"
    return 1
  fi
  printf '%s\n' "$commit" > "$temporal/.candidate-commit"

  for respaldo in "$padre/.${dominio}.previous."*; do
    [ -e "$respaldo" ] || continue
    if [ ! -e "$candidato" ] && [ ! -L "$candidato" ]; then
      mv "$respaldo" "$candidato" || { rm -rf "$temporal"; fail "$dominio: no se pudo recuperar el candidato previo"; return 1; }
    else
      rm -rf "$respaldo"
    fi
  done

  if [ -e "$candidato" ] || [ -L "$candidato" ]; then
    anterior="$padre/.${dominio}.previous.$$"
    rm -rf "$anterior"
    if ! mv "$candidato" "$anterior"; then
      rm -rf "$temporal"
      fail "$dominio: no se pudo apartar el candidato anterior"
      return 1
    fi
  fi
  if ! err=$(mv "$temporal" "$candidato" 2>&1); then
    [ -z "$anterior" ] || mv "$anterior" "$candidato"
    rm -rf "$temporal"
    fail "$dominio: no se pudo publicar el candidato — $err"
    return 1
  fi
  [ -z "$anterior" ] || rm -rf "$anterior"
  return 0
}

# Sincronización de un dominio
# Solo publica el commit de la rama fija que corresponde al runtime seleccionado.
sync_repo() {
  local url="$1" dominio="$2" bare commit err
  if [ "${CANDIDATE_REPO_LOCK_HELD:-0}" != "1" ]; then
    candidate_lock_repo_run "$dominio" -- env CANDIDATE_REPO_LOCK_HELD=1 "$0" __sync-repo "$url" "$dominio"
    return $?
  fi
  ensure_bare "$url" "$dominio" || return 1
  bare="$BARE_RESULT"
  if ! commit=$(git -C "$bare" rev-parse --verify "refs/remotes/origin/$RAMA^{commit}" 2>/dev/null); then
    fail "$dominio: origin/$RAMA no existe, no se puede sincronizar"
    return 1
  fi
  publicar_candidato "$bare" "$dominio" "$commit" || return 1
  ui_ok "$dominio: candidato $ENTORNO actualizado a ${commit:0:12} desde origin/$RAMA"
}

cmd_sync() {
  local indice=0
  require_catalogo
  if ! catalogo_validar; then exit 1; fi
  ui_plan_start "repo-sync ($ENTORNO)"
  ui_step 1 "Publicación de candidatos desde origin/$RAMA declarados en runtime/addons/catalogo.txt."
  if [ "$DOMINIO_COUNT" -eq 0 ]; then
    ui_skip "el catálogo no declara dominios; no hay candidatos para sincronizar"
    ui_plan_end
    return 0
  fi
  mkdir -p "$BARE_DIR" "$CANDIDATE_ROOT"
  while [ "$indice" -lt "$DOMINIO_COUNT" ]; do
    if ! sync_repo "${URLS[$indice]}" "${DOMINIOS[$indice]}"; then FAILED=1; fi
    indice=$((indice + 1))
  done
  ui_plan_end
  if [ "$FAILED" -ne 0 ]; then
    ui_bad "repo-sync terminó con errores" "los candidatos que fallaron conservan su versión anterior" >&2
    echo
    exit 1
  fi
  ui_ok "repo-sync listo — $DOMINIO_COUNT candidato(s) de $ENTORNO sincronizado(s)"
  echo
}

# Estado de candidatos
# Muestra el commit publicado y señala dominios que ya no aparecen en el catálogo.
cmd_status() {
  local indice=0 dominio candidato commit conocidos=" " ruta nombre
  require_catalogo
  if ! catalogo_validar; then exit 1; fi
  printf 'runtime: %s · rama: %s\n\n' "$ENTORNO" "$RAMA"
  printf '%-24s %-16s %s\n' "dominio" "estado" "commit"
  while [ "$indice" -lt "$DOMINIO_COUNT" ]; do
    dominio="${DOMINIOS[$indice]}"
    conocidos="$conocidos$dominio "
    candidato="$CANDIDATE_ROOT/$dominio"
    if [ -f "$candidato/.candidate-commit" ]; then
      commit=$(cat "$candidato/.candidate-commit")
      printf '%-24s %-16s %s\n' "$dominio" "publicado" "$commit"
    else
      printf '%-24s %-16s %s\n' "$dominio" "sin candidato" "-"
    fi
    indice=$((indice + 1))
  done
  for ruta in "$CANDIDATE_ROOT"/*; do
    [ -d "$ruta" ] || [ -L "$ruta" ] || continue
    nombre=$(basename "$ruta")
    case "$conocidos" in
      *" $nombre "*) ;;
      *) printf 'huérfano: custom/%s/%s (no está en runtime/addons/catalogo.txt)\n' "$ENTORNO" "$nombre" ;;
    esac
  done
}

case "${1:-}" in
  __sync-repo) shift; sync_repo "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  status) shift; cmd_status "$@" ;;
  enterprise) shift; cmd_enterprise "$@" ;;
  enterprise-sync) shift; enterprise_sync "$@" ;;
  enterprise-status) shift; enterprise_status "$@" ;;
  enterprise-validate) shift; enterprise_validate "$@" ;;
  *) printf 'uso: %s sync|status|enterprise\n' "$(basename "$0")" >&2; exit 2 ;;
esac
