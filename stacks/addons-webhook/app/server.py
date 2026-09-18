#!/usr/bin/env python3
"""Receptor limitado a publicar candidatos de ramas de integración."""

from __future__ import annotations

import base64
import ctypes
import errno
import fcntl
import hashlib
import hmac
import http.server
import json
import logging
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from urllib.parse import unquote, urlsplit


LOGGER = logging.getLogger("addons-webhook")
MAX_BODY_BYTES = 1_048_576
DOMAIN_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
COMMIT_PATTERN = re.compile(r"^[0-9a-fA-F]{40,64}$")
DELIVERY_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
BRANCH_PATTERN = re.compile(r"^([0-9]+\.0)(?:-stag)?$")


# Configuración de rutas
# Los valores por defecto sirven al test; Compose declara las rutas de producción.
@dataclass(frozen=True)
class Config:
    catalog_path: Path
    bare_dir: Path
    candidate_root: Path
    state_dir: Path
    secret_file: Path
    project_name: str = "default"
    git_token_file: Path | None = None
    git_key_file: Path | None = None
    git_known_hosts_file: Path | None = None
    host: str = "0.0.0.0"
    port: int = 8080

    @classmethod
    def from_env(cls) -> "Config":
        file_path = Path(__file__).resolve()
        root = file_path.parents[3] if len(file_path.parents) > 3 else file_path.parent
        return cls(
            catalog_path=Path(os.environ.get("ADDONS_CATALOG", root / "runtime/addons/catalogo.txt")),
            bare_dir=Path(os.environ.get("ADDONS_BARE_DIR", root / "runtime/addons/.repos")),
            candidate_root=Path(os.environ.get("ADDONS_CANDIDATE_ROOT", root / "runtime/addons/custom")),
            state_dir=Path(os.environ.get("ADDONS_STATE_DIR", root / "runtime/control/state")),
            secret_file=Path(os.environ.get("ADDONS_SECRET_FILE", root / "runtime/control/secrets/addons_webhook_secret")),
            project_name=os.environ.get("ADDONS_PROJECT_NAME", "default"),
            git_token_file=Path(os.environ.get("ADDONS_GIT_TOKEN_FILE", root / "runtime/control/secrets/git_readonly_token")),
            git_key_file=Path(os.environ.get("ADDONS_GIT_SSH_KEY_FILE", root / "runtime/control/secrets/git_readonly_key")),
            git_known_hosts_file=Path(os.environ.get("ADDONS_GIT_KNOWN_HOSTS_FILE", root / "runtime/control/secrets/git_known_hosts")),
            host=os.environ.get("ADDONS_WEBHOOK_HOST", "0.0.0.0"),
            port=int(os.environ.get("ADDONS_WEBHOOK_PORT", "8080")),
        )


class WebhookError(Exception):
    def __init__(self, status: int, reason: str):
        super().__init__(reason)
        self.status = status
        self.reason = reason


class GitOperationError(Exception):
    pass


# Exclusión mutua
# El receptor, repo-sync y los builds usan la misma jerarquía de archivos.
@contextmanager
def file_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_CREAT | os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "a+b") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def environment_lock(config: Config, environment: str) -> Path:
    return config.state_dir / "locks" / config.project_name / f"{environment}.lock"


def repository_lock(config: Config, domain: str) -> Path:
    return config.state_dir / "locks" / "repos" / f"{domain}.lock"


def delivery_lock(config: Config, delivery_id: str) -> Path:
    digest = hashlib.sha256(delivery_id.encode("utf-8")).hexdigest()
    return config.state_dir / "locks" / "deliveries" / f"{digest}.lock"


# Catálogo permitido
# Cada entrada conserva la URL fuente y deriva un nombre de directorio seguro.
def repository_domain(url: str) -> str:
    parsed = urlsplit(url)
    path = parsed.path if parsed.scheme else url
    path = path.rstrip("/")
    name = path.rsplit("/", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    if not DOMAIN_PATTERN.fullmatch(name):
        raise ValueError("nombre de dominio inválido en catálogo")
    return name


def validate_catalog_url(url: str) -> None:
    if "?" in url or "#" in url:
        raise ValueError("URL Git no admitida en catálogo")
    if url.startswith("git@") and ":" in url:
        host, path = url[4:].split(":", 1)
        if host and path and not any(char.isspace() for char in url) and "?" not in url and "#" not in url:
            return
    parsed = urlsplit(url)
    if parsed.scheme in {"https", "ssh"}:
        user_allowed = parsed.username is None or (parsed.scheme == "ssh" and parsed.username == "git")
        if parsed.hostname and parsed.path and parsed.password is None and user_allowed:
            return
    if parsed.scheme == "file" and parsed.path:
        return
    if url.startswith(("/", "./", "../")):
        return
    raise ValueError("URL Git no admitida en catálogo")


def read_catalog(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise WebhookError(503, "falta el catálogo de repositorios")
    entries = []
    domains = set()
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise WebhookError(503, "no se pudo leer el catálogo") from error
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split()
        if len(parts) != 1:
            raise WebhookError(503, "el catálogo contiene una entrada inválida")
        url = parts[0]
        try:
            validate_catalog_url(url)
            domain = repository_domain(url)
        except ValueError as error:
            raise WebhookError(503, "el catálogo contiene una entrada inválida") from error
        if domain == "enterprise":
            raise WebhookError(503, "Enterprise se administra fuera del catálogo")
        if domain in domains:
            raise WebhookError(503, "el catálogo repite un dominio")
        domains.add(domain)
        entries.append({"domain": domain, "url": url})
    return entries


# Identidad de repositorio
# Acepta las URL GitHub y SSH equivalentes sin confundir dominios homónimos.
def repository_key(url: str) -> tuple[str, str] | None:
    if url.startswith("git@") and ":" in url:
        host, path = url[4:].split(":", 1)
        scheme = "remote"
    else:
        parsed = urlsplit(url)
        scheme = parsed.scheme
        if scheme in {"https", "ssh"} and parsed.hostname:
            host, path = parsed.hostname.lower(), parsed.path
        elif scheme == "file":
            return "file", os.path.realpath(unquote(parsed.path))
        elif not scheme and url.startswith(("/", "./", "../")):
            return "file", os.path.realpath(url)
        else:
            return None
    path = path.rstrip("/")
    if path.endswith(".git"):
        path = path[:-4]
    if not host or not path:
        return None
    return "remote", f"{host}/{path}".casefold()


def repository_matches(entry: dict[str, str], repository: dict) -> bool:
    expected = repository_key(entry["url"])
    urls = [repository.get(field) for field in ("clone_url", "ssh_url", "html_url")]
    urls = [value for value in urls if isinstance(value, str) and value]
    if urls:
        return any(repository_key(value) == expected for value in urls)
    full_name = repository.get("full_name")
    if isinstance(full_name, str) and expected is not None and expected[0] == "remote":
        return expected[1].split("/", 1)[-1] == full_name.casefold().strip("/")
    return False


# Selección de ramas operativas
# El servidor solo recibe staging y producción; las features se prueban localmente.
def environment_for_branch(ref: str) -> tuple[str, str] | None:
    prefix = "refs/heads/"
    if not ref.startswith(prefix):
        return None
    branch = ref[len(prefix):]
    match = BRANCH_PATTERN.fullmatch(branch)
    if not match:
        return None
    if branch.endswith("-stag"):
        return "staging", branch
    return "produccion", branch


def configured_odoo_version(config: Config) -> str:
    version_path = config.state_dir / "odoo-version"
    try:
        version = version_path.read_text(encoding="ascii").strip()
    except (OSError, UnicodeError) as error:
        raise WebhookError(503, "falta la línea de Odoo inicializada por config-init") from error
    if not re.fullmatch(r"[0-9]+\.0", version):
        raise WebhookError(503, "la línea de Odoo inicializada no es válida")
    return version


# Operaciones Git acotadas
# El proceso nunca invoca Docker ni interpreta contenido del payload como comando.
def git_credentials(config: Config, remote_url: str | None) -> dict[str, str]:
    if remote_url is None:
        return {}
    parsed = urlsplit(remote_url)
    if parsed.scheme == "https" and parsed.hostname and config.git_token_file and config.git_token_file.is_file():
        try:
            token = config.git_token_file.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError) as error:
            raise GitOperationError("no se pudo leer la credencial Git de solo lectura") from error
        if token:
            encoded = base64.b64encode(f"x-access-token:{token}".encode("utf-8")).decode("ascii")
            host = parsed.hostname.lower()
            return {
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": f"http.https://{host}/.extraheader",
                "GIT_CONFIG_VALUE_0": f"AUTHORIZATION: basic {encoded}",
            }
    is_ssh = remote_url.startswith("git@") or parsed.scheme == "ssh"
    if is_ssh and config.git_key_file and config.git_known_hosts_file:
        if config.git_key_file.is_file() and config.git_known_hosts_file.is_file():
            command = [
                "ssh",
                "-F",
                os.devnull,
                "-i",
                str(config.git_key_file),
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                f"UserKnownHostsFile={config.git_known_hosts_file}",
            ]
            return {"GIT_SSH_COMMAND": shlex.join(command)}
    return {}


def run_git(
    arguments: list[str],
    *,
    config: Config,
    remote_url: str | None = None,
    cwd: Path | None = None,
    stdout=None,
) -> str:
    environment = os.environ.copy()
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = os.devnull
    environment.update(git_credentials(config, remote_url))
    try:
        result = subprocess.run(
            ["git", *arguments],
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=stdout if stdout is not None else subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            text=stdout is None,
            timeout=300,
        )
    except subprocess.TimeoutExpired as error:
        raise GitOperationError("se agotó el tiempo de una operación Git") from error
    except OSError as error:
        raise GitOperationError("no se pudo ejecutar Git") from error
    if result.returncode != 0:
        raise GitOperationError("falló una operación Git")
    return result.stdout.strip() if isinstance(result.stdout, str) else ""


def ensure_directory(path: Path) -> None:
    if path.is_symlink():
        raise WebhookError(500, "una ruta de trabajo no es segura")
    path.mkdir(parents=True, exist_ok=True)
    if not path.is_dir():
        raise WebhookError(500, "una ruta de trabajo no es un directorio")


def ensure_bare_repository(entry: dict[str, str], config: Config) -> Path:
    ensure_directory(config.bare_dir)
    bare = config.bare_dir / f"{entry['domain']}.git"
    if bare.is_symlink():
        raise WebhookError(500, "el clon bare no es una ruta segura")
    if not bare.exists():
        try:
            run_git(["clone", "--bare", "--", entry["url"], str(bare)], config=config, remote_url=entry["url"])
        except GitOperationError:
            if bare.is_dir() and not bare.is_symlink():
                shutil.rmtree(bare, ignore_errors=True)
            raise
    if not bare.is_dir() or run_git(["-C", str(bare), "rev-parse", "--is-bare-repository"], config=config) != "true":
        raise WebhookError(409, "el clon bare existente no es válido")
    remote = run_git(["-C", str(bare), "remote", "get-url", "origin"], config=config)
    if remote != entry["url"]:
        raise WebhookError(409, "la URL del catálogo difiere del clon bare")
    return bare


def safe_extract(archive_file, destination: Path) -> None:
    with tarfile.open(fileobj=archive_file, mode="r:") as archive:
        members = archive.getmembers()
        for member in members:
            member_path = PurePosixPath(member.name)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise GitOperationError("el commit contiene una ruta inválida")
        try:
            archive.extractall(destination, members=members, filter="data")
        except TypeError as error:
            # Python < 3.12 no conoce `filter`; en ese caso rechazamos enlaces
            # y archivos especiales antes de usar la extracción validada arriba.
            if "filter" not in str(error):
                raise GitOperationError("no se pudo extraer el commit") from error
            if any(member.issym() or member.islnk() or member.isdev() for member in members):
                raise GitOperationError("el commit contiene un tipo de archivo no admitido")
            try:
                archive.extractall(destination, members=members)
            except (OSError, tarfile.TarError, ValueError) as error:
                raise GitOperationError("no se pudo extraer el commit") from error
        except (OSError, tarfile.TarError, ValueError) as error:
            raise GitOperationError("no se pudo extraer el commit") from error


def clean_path(path: Path) -> None:
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        path.unlink(missing_ok=True)
    elif path.exists():
        shutil.rmtree(path)


# Reemplazo atómico de directorio
# Linux intercambia ambas entradas; otros sistemas conservan rollback bajo el lock.
def exchange_paths(first: Path, second: Path) -> bool:
    if not sys.platform.startswith("linux"):
        return False
    try:
        renameat2 = ctypes.CDLL(None, use_errno=True).renameat2
    except AttributeError:
        return False
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    result = renameat2(-100, os.fsencode(first), -100, os.fsencode(second), 2)
    if result == 0:
        return True
    error = ctypes.get_errno()
    if error in {errno.ENOSYS, errno.EINVAL, errno.EOPNOTSUPP, errno.EXDEV, errno.ENOTDIR}:
        return False
    raise OSError(error, os.strerror(error))


def recover_candidate(candidate: Path, domain: str) -> None:
    parent = candidate.parent
    backups = sorted(parent.glob(f".{domain}.previous.*"), key=lambda path: path.lstat().st_mtime_ns)
    if not candidate.exists() and not candidate.is_symlink() and backups:
        os.replace(backups.pop(), candidate)
    for backup in backups:
        clean_path(backup)
    for temporary in parent.glob(f".{domain}.*"):
        if not temporary.name.startswith(f".{domain}.previous."):
            clean_path(temporary)


def publish_candidate(bare: Path, domain: str, environment: str, commit: str, config: Config) -> None:
    candidate_parent = config.candidate_root / environment
    ensure_directory(config.candidate_root)
    ensure_directory(candidate_parent)
    candidate = candidate_parent / domain
    if candidate.is_symlink():
        raise WebhookError(500, "el candidato existente no es una ruta segura")
    recover_candidate(candidate, domain)

    temporary = Path(tempfile.mkdtemp(prefix=f".{domain}.", dir=candidate_parent))
    backup: Path | None = None
    try:
        with tempfile.TemporaryFile(dir=config.state_dir) as archive_file:
            run_git(
                ["-C", str(bare), "archive", "--format=tar", commit],
                config=config,
                stdout=archive_file,
            )
            archive_file.seek(0)
            safe_extract(archive_file, temporary)
        (temporary / ".candidate-commit").write_text(f"{commit}\n", encoding="ascii")

        if candidate.exists() and exchange_paths(temporary, candidate):
            clean_path(temporary)
        else:
            if candidate.exists():
                backup = candidate_parent / f".{domain}.previous.{os.getpid()}.{uuid.uuid4().hex}"
                os.replace(candidate, backup)
            try:
                os.replace(temporary, candidate)
            except OSError:
                if backup is not None and backup.exists():
                    os.replace(backup, candidate)
                    backup = None
                raise
            if backup is not None:
                clean_path(backup)
    finally:
        if temporary.exists():
            clean_path(temporary)


def sync_candidate(entry: dict[str, str], branch: str, environment: str, config: Config) -> str:
    domain = entry["domain"]
    with file_lock(repository_lock(config, domain)):
        bare = ensure_bare_repository(entry, config)
        refspec = f"+refs/heads/{branch}:refs/remotes/origin/{branch}"
        run_git(["-C", str(bare), "fetch", "--no-tags", "origin", refspec], config=config, remote_url=entry["url"])
        commit = run_git(
            ["-C", str(bare), "rev-parse", "--verify", f"refs/remotes/origin/{branch}^{{commit}}"],
            config=config,
        )
        if not COMMIT_PATTERN.fullmatch(commit):
            raise GitOperationError("Git devolvió un identificador de commit inválido")
        publish_candidate(bare, domain, environment, commit, config)
        return commit


# Registro de entregas
# Guarda el resultado por identificador para responder reintentos sin duplicar trabajo.
def delivery_record_path(config: Config, delivery_id: str) -> Path:
    digest = hashlib.sha256(delivery_id.encode("utf-8")).hexdigest()
    return config.state_dir / "deliveries" / f"{digest}.json"


def read_delivery_record(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError, UnicodeError) as error:
        raise WebhookError(500, "no se pudo leer el estado de entregas") from error


def write_delivery_record(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".delivery.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(record, output, ensure_ascii=False, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def header(headers, name: str) -> str:
    if hasattr(headers, "get"):
        value = headers.get(name)
        if value is not None:
            return value
    for key, value in headers.items():
        if key.lower() == name.lower():
            return value
    return ""


def json_response(status: int, message: str, **fields) -> tuple[int, dict]:
    return status, {"status": message, **fields}


# Procesamiento del webhook
# Firma, allowlist y rama se validan antes de tocar Git o los candidatos.
def process_delivery(config: Config, headers, body: bytes) -> tuple[int, dict]:
    try:
        secret = config.secret_file.read_bytes()
    except OSError as error:
        raise WebhookError(503, "no está disponible el secreto de firma") from error
    if len(secret) < 32:
        raise WebhookError(503, "el secreto de firma debe tener al menos 32 bytes")

    signature = header(headers, "X-Hub-Signature-256")
    if not isinstance(signature, str) or not re.fullmatch(r"sha256=[0-9a-fA-F]{64}", signature):
        raise WebhookError(401, "firma inválida")
    expected = "sha256=" + hmac.new(secret, body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature.lower(), expected):
        raise WebhookError(401, "firma inválida")

    event = header(headers, "X-GitHub-Event")
    if event != "push":
        return json_response(202, "ignored", reason="evento no admitido")
    delivery_id = header(headers, "X-GitHub-Delivery")
    if not isinstance(delivery_id, str) or not DELIVERY_PATTERN.fullmatch(delivery_id):
        raise WebhookError(400, "falta un identificador de entrega válido")
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise WebhookError(400, "el cuerpo no contiene JSON válido") from error
    if not isinstance(payload, dict):
        raise WebhookError(400, "el cuerpo debe ser un objeto JSON")

    ref = payload.get("ref", "")
    target = environment_for_branch(ref) if isinstance(ref, str) else None
    after = payload.get("after", "")
    if target is None or payload.get("deleted") is True or not isinstance(after, str) or not COMMIT_PATTERN.fullmatch(after):
        return json_response(202, "ignored", reason="rama o commit fuera de integración")

    repository = payload.get("repository")
    if not isinstance(repository, dict):
        return json_response(202, "ignored", reason="repositorio fuera del catálogo")
    try:
        entries = read_catalog(config.catalog_path)
    except WebhookError:
        raise
    entry = next((item for item in entries if repository_matches(item, repository)), None)
    if entry is None:
        return json_response(202, "ignored", reason="repositorio fuera del catálogo")

    environment, branch = target
    configured_version = configured_odoo_version(config)
    if branch.split("-", 1)[0] != configured_version:
        return json_response(202, "ignored", reason="rama de otra línea de Odoo")
    record_path = delivery_record_path(config, delivery_id)
    with file_lock(delivery_lock(config, delivery_id)):
        previous = read_delivery_record(record_path)
        if previous is not None:
            return json_response(200, "duplicate", result=previous.get("result", "processed"))
        with file_lock(environment_lock(config, environment)):
            commit = sync_candidate(entry, branch, environment, config)
        record = {
            "delivery_id": delivery_id,
            "repository": repository.get("full_name", entry["domain"]),
            "domain": entry["domain"],
            "branch": branch,
            "commit": commit,
            "environment": environment,
            "received_at": datetime.now(timezone.utc).isoformat(),
            "result": "candidate updated",
        }
        write_delivery_record(record_path, record)
    return json_response(200, "updated", domain=entry["domain"], environment=environment, commit=commit)


# Servidor HTTP
# Expone healthcheck y un único endpoint interno para GitHub.
class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "addons-webhook"
    sys_version = ""

    def log_message(self, format_string, *args) -> None:
        LOGGER.info("http status=%s", args[1] if len(args) > 1 else "unknown")

    def send_json(self, status: int, payload: dict) -> None:
        output = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(output)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(output)

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self.send_json(200, {"status": "ok"})
            return
        self.send_json(404, {"status": "not-found"})

    def do_POST(self) -> None:
        if self.path != "/github":
            self.send_json(404, {"status": "not-found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            self.send_json(400, {"status": "error", "reason": "Content-Length inválido"})
            return
        if length < 0:
            self.send_json(411, {"status": "error", "reason": "se requiere Content-Length"})
            return
        if length > MAX_BODY_BYTES:
            self.send_json(413, {"status": "error", "reason": "cuerpo demasiado grande"})
            return
        body = self.rfile.read(length)
        if len(body) != length:
            self.send_json(400, {"status": "error", "reason": "cuerpo incompleto"})
            return
        try:
            status, payload = process_delivery(self.server.config, self.headers, body)
        except WebhookError as error:
            status, payload = json_response(error.status, "error", reason=error.reason)
        except GitOperationError:
            LOGGER.exception("falló la reconciliación Git")
            status, payload = json_response(502, "error", reason="no se pudo actualizar el candidato")
        except OSError:
            LOGGER.exception("falló una operación local del receptor")
            status, payload = json_response(500, "error", reason="no se pudo publicar el candidato")
        self.send_json(status, payload)


def serve(config: Config) -> None:
    server = http.server.ThreadingHTTPServer((config.host, config.port), Handler)
    server.config = config
    LOGGER.info("receptor listo en %s:%s", config.host, config.port)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()


if __name__ == "__main__":
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
    serve(Config.from_env())
