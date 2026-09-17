#!/usr/bin/env bash
# Dependencias Python de los addons
# Los repositorios deciden cómo instalar; los manifiestos solo comprueban cobertura.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/lib/ui.sh
. scripts/lib/contexto.sh
contexto_iniciar

OVERRIDE="${PYDEPS_OVERRIDE:-runtime/addons/requirements.override.txt}"
OUTPUT="${PYDEPS_OUTPUT:-runtime/addons/requirements.lock.txt}"

# Snapshot del runtime
# Los comandos manuales leen candidatos; el build inyecta la fotografía exportada.
if [ -n "${PYDEPS_SNAPSHOT_ROOT:-}" ]; then
  ENTERPRISE_ROOT="$PYDEPS_SNAPSHOT_ROOT/enterprise"
  CUSTOM_ROOT="$PYDEPS_SNAPSHOT_ROOT/custom"
else
  ENTERPRISE_ROOT="runtime/addons/enterprise"
  CUSTOM_ROOT="runtime/addons/custom/$ENTORNO"
fi

# Analizador y compilador
# Python valida los formatos sin ejecutar manifiestos y conserva cada requisito literal.
run_pydeps() {
  local command="$1"
  python3 - "$command" "$ENTERPRISE_ROOT" "$CUSTOM_ROOT" "$OVERRIDE" "$OUTPUT" <<'PY'
import ast
import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

command, enterprise_arg, custom_arg, override_arg, output_arg = sys.argv[1:]
roots = [pathlib.Path(enterprise_arg), pathlib.Path(custom_arg)]
override = pathlib.Path(override_arg)
output = pathlib.Path(output_arg)

ALIASES = {
    "openssl": "pyopenssl",
    "pil": "pillow",
    "yaml": "pyyaml",
    "dateutil": "python-dateutil",
    "jwt": "pyjwt",
    "magic": "python-magic",
    "ldap": "python-ldap",
}
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*")
EXACT_RE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*==\s*([^,;\s]+)")


def normalize(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def source_label(path):
    for root in roots:
        try:
            return str(path.relative_to(root.parent))
        except ValueError:
            pass
    return str(path)


def requirements_files():
    files = []
    for root in roots:
        if root.is_dir():
            files.extend(root.rglob("requirements.txt"))
    files = sorted(set(files), key=lambda path: str(path))
    if override.is_file():
        files.append(override)
    return files


def requirement_lines(path):
    lines = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("-r ", "--requirement ", "-c ", "--constraint ", "-e ", "--editable ")):
            raise ValueError(
                f"{path}:{number}: directiva no soportada; declarar el requisito directamente"
            )
        if line.startswith("-"):
            raise ValueError(f"{path}:{number}: opción de pip no soportada: {line}")
        lines.append((line, path, number))
    return lines


def split_marker(line):
    requirement, separator, marker = line.partition(";")
    suffix = f";{marker}" if separator else ""
    return requirement.strip(), suffix


def vcs_parts(requirement):
    prefix = ""
    vcs = requirement
    if " @ git+" in requirement:
        prefix, vcs = requirement.split(" @ ", 1)
        prefix = prefix.strip() + " @ "
    if not vcs.startswith("git+"):
        return None

    url_and_ref, hash_separator, fragment = vcs[4:].partition("#")
    at = url_and_ref.rfind("@")
    last_slash = url_and_ref.rfind("/")
    if at > last_slash:
        url, ref = url_and_ref[:at], url_and_ref[at + 1 :]
    else:
        url, ref = url_and_ref, "HEAD"
    suffix = f"#{fragment}" if hash_separator else ""
    return prefix, url, ref, suffix


def requirement_name(line):
    requirement, _marker = split_marker(line)
    vcs = vcs_parts(requirement)
    if vcs:
        prefix, url, _ref, fragment = vcs
        if prefix:
            return normalize(prefix[:-3].strip())
        egg = re.search(r"(?:^|&)egg=([^&]+)", fragment.lstrip("#"))
        if egg:
            return normalize(egg.group(1))
        repository = url.rstrip("/").rsplit("/", 1)[-1]
        return normalize(repository.removesuffix(".git"))
    if " @ " in requirement:
        return normalize(requirement.split(" @ ", 1)[0].strip())
    if requirement.startswith(("http://", "https://")):
        return None
    match = NAME_RE.match(requirement)
    return normalize(match.group(0)) if match else None


def manifest_dependencies():
    declared = {}
    invalid = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("__manifest__.py")):
            try:
                manifest = ast.literal_eval(path.read_text(encoding="utf-8"))
            except (OSError, SyntaxError, UnicodeError, ValueError) as error:
                invalid.append(f"{path}: {error}")
                continue
            if not isinstance(manifest, dict):
                invalid.append(f"{path}: debe ser un diccionario")
                continue
            dependencies = manifest.get("external_dependencies", {})
            if not isinstance(dependencies, dict):
                invalid.append(f"{path}: external_dependencies debe ser un diccionario")
                continue
            python_dependencies = dependencies.get("python", [])
            if not isinstance(python_dependencies, (list, tuple)) or not all(
                isinstance(item, str) for item in python_dependencies
            ):
                invalid.append(
                    f"{path}: external_dependencies.python debe ser una lista de textos"
                )
                continue
            for dependency in python_dependencies:
                match = NAME_RE.match(dependency.strip())
                if not match:
                    invalid.append(f"{path}: dependencia Python inválida: {dependency}")
                    continue
                imported = normalize(match.group(0))
                installed = ALIASES.get(imported, imported)
                declared.setdefault(installed, []).append(path)
    if invalid:
        raise ValueError("manifiestos inválidos:\n" + "\n".join(invalid))
    return declared


def collect_requirements():
    collected = []
    files = requirements_files()
    repository_files = [path for path in files if path != override]
    for path in repository_files:
        for line, source, number in requirement_lines(path):
            name = requirement_name(line)
            if not name:
                raise ValueError(f"{source}:{number}: requisito no reconocido: {line}")
            collected.append((line, name, source, number))
    if override.is_file():
        override_requirements = []
        for line, source, number in requirement_lines(override):
            name = requirement_name(line)
            if not name:
                raise ValueError(f"{source}:{number}: requisito no reconocido: {line}")
            override_requirements.append((line, name, source, number))
        overridden = {name for _line, name, _source, _number in override_requirements}
        collected = [item for item in collected if item[1] not in overridden]
        collected.extend(override_requirements)
    return collected


def validate(declared, collected):
    installed = {name for _line, name, _source, _number in collected}
    missing = sorted(set(declared) - installed)
    if missing:
        details = []
        for name in missing:
            sources = ", ".join(sorted({str(path) for path in declared[name]}))
            details.append(f"{name} (declarada en {sources})")
        raise ValueError("dependencias sin requirements.txt: " + "; ".join(details))

    exact = {}
    direct = {}
    indexed = set()
    for line, name, source, number in collected:
        requirement, _marker = split_marker(line)
        match = EXACT_RE.match(requirement)
        if match:
            exact.setdefault(name, {}).setdefault(match.group(2), []).append((source, number))
        if vcs_parts(requirement) or " @ " in requirement:
            direct.setdefault(name, {}).setdefault(requirement, []).append((source, number))
        else:
            indexed.add(name)
    conflicts = []
    for name, versions in exact.items():
        if len(versions) > 1:
            conflicts.append(f"{name}: pines incompatibles {', '.join(sorted(versions))}")
    for name, references in direct.items():
        if len(references) > 1:
            conflicts.append(f"{name}: fuentes directas incompatibles")
        if name in indexed:
            conflicts.append(f"{name}: mezcla una fuente directa con un requisito de índice")
    if conflicts:
        raise ValueError("requisitos incompatibles: " + "; ".join(conflicts))


def resolve_vcs(line, sources_dir, checkout_root, mirrors):
    requirement, marker = split_marker(line)
    vcs = vcs_parts(requirement)
    if not vcs:
        return line, None
    prefix, url, ref, fragment = vcs
    if re.fullmatch(r"[0-9a-fA-F]{40}", ref):
        sha = ref.lower()
    else:
        patterns = ["HEAD"] if ref == "HEAD" else [
            f"refs/heads/{ref}",
            f"refs/tags/{ref}^{{}}",
            f"refs/tags/{ref}",
        ]
        environment = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        result = subprocess.run(
            ["git", "ls-remote", url, *patterns],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
            env=environment,
        )
        if result.returncode != 0:
            message = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "sin detalle"
            raise ValueError(f"no se pudo resolver {url}@{ref}: {message}")
        references = {}
        for row in result.stdout.splitlines():
            sha_value, remote_ref = row.split("\t", 1)
            references[remote_ref] = sha_value
        preferred = ["HEAD"] if ref == "HEAD" else [
            f"refs/tags/{ref}^{{}}",
            f"refs/heads/{ref}",
            f"refs/tags/{ref}",
        ]
        sha = next((references[item] for item in preferred if item in references), None)
        if not sha:
            raise ValueError(f"no existe la referencia Git {url}@{ref}")

    mirror = mirrors.get(url)
    if mirror is None:
        mirror = checkout_root / hashlib.sha256(url.encode()).hexdigest()
        environment = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        result = subprocess.run(
            ["git", "clone", "--mirror", "--quiet", url, str(mirror)],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
            env=environment,
        )
        if result.returncode != 0:
            message = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "sin detalle"
            raise ValueError(f"no se pudo descargar {url}: {message}")
        mirrors[url] = mirror

    repository = normalize(url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git"))
    filename = f"{repository}-{sha[:12]}-{hashlib.sha256(url.encode()).hexdigest()[:8]}.tar.gz"
    archive = sources_dir / filename
    result = subprocess.run(
        ["git", f"--git-dir={mirror}", "archive", "--format=tar.gz", f"--output={archive}", sha],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        message = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "sin detalle"
        raise ValueError(f"no se pudo archivar {url}@{sha}: {message}")
    with tarfile.open(archive, "r:gz") as source_archive:
        if any(member.name == ".gitmodules" for member in source_archive.getmembers()):
            raise ValueError(f"{url}@{sha} usa submódulos Git, formato todavía no soportado")

    local = f"file:///tmp/requirements.sources/{filename}{fragment}"
    compiled = f"{prefix}{local}{marker}" if prefix else f"{local}{marker}"
    return compiled, f"{url}@{sha}{fragment}"


try:
    declared = manifest_dependencies()
    collected = collect_requirements()
    validate(declared, collected)
    if command == "compile":
        compiled = []
        seen = set()
        current_source = None
        sources_dir = output.parent / "requirements.sources"
        if sources_dir.exists():
            shutil.rmtree(sources_dir)
        sources_dir.mkdir(parents=True)
        with tempfile.TemporaryDirectory(prefix="pydeps-") as checkout:
            checkout_root = pathlib.Path(checkout)
            mirrors = {}
            for line, _name, source, _number in collected:
                resolved, provenance = resolve_vcs(line, sources_dir, checkout_root, mirrors)
                if resolved in seen:
                    continue
                if source != current_source:
                    compiled.append(f"# Fuente: {source_label(source)}")
                    current_source = source
                if provenance:
                    compiled.append(f"# VCS: {provenance}")
                compiled.append(resolved)
                seen.add(resolved)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text("\n".join(compiled) + ("\n" if compiled else ""), encoding="utf-8")
        print(f"{len(seen)} requisito(s) compilados en {output}")
    elif command == "check":
        print(f"{len(collected)} requisito(s) cubren {len(declared)} dependencia(s) declaradas")
    else:
        raise ValueError(f"comando desconocido: {command}")
except (OSError, subprocess.TimeoutExpired, ValueError) as error:
    print(f"pydeps: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
}

# Verificación offline
# Confirma sintaxis, cobertura de manifiestos y ausencia de conflictos evidentes.
cmd_check() {
  local report
  ui_plan_start "pydeps check"
  ui_step 1 "Validación de requirements.txt de los repositorios y overrides del entorno."
  if ! report=$(run_pydeps check 2>&1); then
    ui_bad "pydeps check: requisitos inválidos" "$report"
    ui_plan_end
    return 1
  fi
  ui_plan_end
  ui_ok "pydeps check: $report"
  echo
}

# Compilación reproducible
# Fija ramas y tags Git a commits completos antes de escribir el lock del build.
cmd_compile() {
  local report
  ui_plan_start "pydeps compile"
  ui_step 1 "Compilación de requirements.txt desde la fotografía de addons."
  if ! report=$(run_pydeps compile 2>&1); then
    ui_bad "pydeps compile: no se pudo generar el lock" "$report"
    ui_plan_end
    return 1
  fi
  ui_plan_end
  ui_ok "pydeps compile: $report"
  echo
}

case "${1:-}" in
  check) cmd_check ;;
  compile) cmd_compile ;;
  *) echo "uso: $(basename "$0") check|compile" >&2; exit 2 ;;
esac
