#!/usr/bin/env bash
# Receptor de candidatos
# Comprueba la publicación pública y las mutaciones controladas por cada push.

cd "$(dirname "$0")/.."
. tests/lib.sh

TMP=$(mktemp -d)
RUNTIME_ENV_CREADO=0
if [ ! -f runtime/produccion/compose.env ]; then
  cp runtime/produccion/compose.env.example runtime/produccion/compose.env
  RUNTIME_ENV_CREADO=1
fi
limpiar() {
  rm -rf "$TMP"
  [ "$RUNTIME_ENV_CREADO" -eq 0 ] || rm -f runtime/produccion/compose.env
}
trap limpiar EXIT

# Ruta pública
# Solo producción monta la ruta activa y el receptor vive en edge sin puertos propios.
PROD=$(docker compose --env-file runtime/produccion/compose.env.example \
  -f runtime/produccion/compose.yaml config)
DEV=$(docker compose --env-file runtime/desarrollo/compose.env.example \
  -f runtime/desarrollo/compose.yaml config)
STAGE=$(docker compose --env-file runtime/staging/compose.env.example \
  -f runtime/staging/compose.yaml config)
contiene "producción declara el receptor" "addons-webhook:" "$PROD"
no_contiene "desarrollo no declara el receptor" "addons-webhook:" "$DEV"
no_contiene "staging no declara el receptor" "addons-webhook:" "$STAGE"
contiene "producción monta la ruta pública real" \
  "/stacks/nginx/config/addons-webhook.locations" "$PROD"
contiene "desarrollo monta la plantilla runtime vacía" \
  "/runtime/desarrollo/config/nginx/addons-webhook.locations" "$DEV"
contiene "staging monta la plantilla runtime vacía" \
  "/runtime/staging/config/nginx/addons-webhook.locations" "$STAGE"
igual "el receptor no publica puertos del host" "" \
  "$(printf '%s\n' "$PROD" | sed -n '/^  addons-webhook:/,/^  [a-z0-9_-]*:$/p' | sed -n 's/^ *published: //p')"

# Verificación del stack
# La fixture devuelve la composición real y simula el servicio detenido.
mkdir -p "$TMP/verify"
printf '%s\n' addons-webhook > "$TMP/verify/servicios"
printf '%s\n' addons-webhook > "$TMP/verify/servicios-sin-perfil"
cp runtime/produccion/compose.env.example "$TMP/verify/config.env"
STUB_DIR="$TMP/verify" docker compose --env-file runtime/produccion/compose.env.example \
  -f runtime/produccion/compose.yaml config > "$TMP/verify/config"
SALIDA=$(STUB_DIR="$TMP/verify" PATH="$PWD/tests/stubs:$PATH" ENTORNO=produccion \
  scripts/verify-stacks.sh addons-webhook 2>&1 || true)
contiene "el stack con guion se descubre y ejecuta" "addons-webhook" "$SALIDA"
contiene "el verify acepta las rutas limitadas de secretos" \
  "solo monta los cuatro secretos dedicados al webhook" "$SALIDA"
no_contiene "el verify no confunde el nombre del checkout con Odoo" \
  "la composición del receptor contiene una referencia prohibida" "$SALIDA"
sed 's@target: /var/lib/addons-webhook@target: /var/run/docker.sock@' \
  "$TMP/verify/config" > "$TMP/verify/config-insegura"
cp "$TMP/verify/config-insegura" "$TMP/verify/config"
SALIDA=$(STUB_DIR="$TMP/verify" PATH="$PWD/tests/stubs:$PATH" ENTORNO=produccion \
  scripts/verify-stacks.sh addons-webhook 2>&1 || true)
contiene "el verify detecta acceso al socket Docker" \
  "la composición del receptor contiene una referencia prohibida" "$SALIDA"

python3 - "$PWD" "$TMP" <<'PY'
import hashlib
import hmac
import io
import importlib.util
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

root = Path(sys.argv[1])
temporary = Path(sys.argv[2]) / "server-tests"
temporary.mkdir()
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("addons_webhook", root / "stacks/addons-webhook/app/server.py")
webhook = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = webhook
spec.loader.exec_module(webhook)
checks = 0
failures = 0

def check(name, condition):
    global checks, failures
    checks += 1
    if condition:
        print(f"  ok      {name}")
    else:
        failures += 1
        print(f"  FALLA   {name}")

original_file = webhook.__file__
webhook.__file__ = "/app/server.py"
environment_paths = {
    "ADDONS_CATALOG": temporary / "env-catalog",
    "ADDONS_BARE_DIR": temporary / "env-bare",
    "ADDONS_CANDIDATE_ROOT": temporary / "env-candidates",
    "ADDONS_STATE_DIR": temporary / "env-state",
    "ADDONS_SECRET_FILE": temporary / "env-secret",
    "ADDONS_GIT_TOKEN_FILE": temporary / "env-token",
    "ADDONS_GIT_SSH_KEY_FILE": temporary / "env-key",
    "ADDONS_GIT_KNOWN_HOSTS_FILE": temporary / "env-known-hosts",
}
previous_environment = {key: os.environ.get(key) for key in environment_paths}
os.environ.update({key: str(value) for key, value in environment_paths.items()})
check("Config funciona desde el WORKDIR /app del contenedor", webhook.Config.from_env().catalog_path == environment_paths["ADDONS_CATALOG"])
for key, value in previous_environment.items():
    if value is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = value
webhook.__file__ = original_file

archive_bytes = io.BytesIO()
with tarfile.open(fileobj=archive_bytes, mode="w:") as archive:
    content = b"contenido seguro\n"
    member = tarfile.TarInfo("README.txt")
    member.size = len(content)
    archive.addfile(member, io.BytesIO(content))
extract_destination = temporary / "safe-extract"
extract_destination.mkdir()
webhook.safe_extract(io.BytesIO(archive_bytes.getvalue()), extract_destination)
check("safe_extract funciona en el Python del host", (extract_destination / "README.txt").read_bytes() == b"contenido seguro\n")

def run(*arguments, cwd=None):
    environment = os.environ.copy()
    environment.update({"GIT_AUTHOR_NAME": "test", "GIT_AUTHOR_EMAIL": "test@example.test", "GIT_COMMITTER_NAME": "test", "GIT_COMMITTER_EMAIL": "test@example.test"})
    subprocess.run(arguments, cwd=cwd, env=environment, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def create_remote(name):
    work = temporary / f"{name}.git"
    work.mkdir()
    run("git", "init", "-q", "-b", "19.0", str(work))
    (work / "__manifest__.py").write_text(f"{{'name': '{name}'}}\n")
    run("git", "-C", str(work), "add", ".")
    run("git", "-C", str(work), "commit", "-qm", "base")
    for branch, content in (("19.0-dev", "desarrollo"), ("19.0-stag", "staging")):
        run("git", "-C", str(work), "checkout", "-qb", branch)
        with (work / "__manifest__.py").open("a") as output:
            output.write(content + "\n")
        run("git", "-C", str(work), "commit", "-qam", branch)
        run("git", "-C", str(work), "checkout", "-q", "19.0")
    return work, work

def commit_for(work, branch):
    return subprocess.check_output(["git", "-C", str(work), "rev-parse", branch], text=True).strip()

work, remote = create_remote("ventas")
work_two, remote_two = create_remote("compras")
catalog = temporary / "catalogo.txt"
catalog.write_text(f"{remote}\n{remote_two}\n")
secret = temporary / "secret"
secret.write_bytes(b"x" * 32)
state = temporary / "state"
state.mkdir()
(state / "odoo-version").write_text("19.0\n")
bare = temporary / "bare"
candidates = temporary / "candidates"
config = webhook.Config(catalog, bare, candidates, state, secret)
active_odoo = temporary / "odoo-active.json"
active_odoo.write_text('{"digest":"sha256:active"}\n')
active_before = active_odoo.read_bytes()

def headers(body, delivery, event="push", key=b"x" * 32):
    signature = "sha256=" + hmac.new(key, body, hashlib.sha256).hexdigest()
    return {"X-Hub-Signature-256": signature, "X-GitHub-Event": event, "X-GitHub-Delivery": delivery}

def send(branch, revision, delivery, url=remote, event="push", key=b"x" * 32):
    body = json.dumps({"ref": f"refs/heads/{branch}", "after": revision, "repository": {"clone_url": str(url)}}).encode()
    try:
        status, result = webhook.process_delivery(config, headers(body, delivery, event, key), body)
        return status, result
    except webhook.WebhookError as error:
        return error.status, {"status": "error", "reason": error.reason}

check("las tres ramas se asignan a su entorno", [webhook.environment_for_branch(f"refs/heads/{b}")[0] for b in ("19.0-dev", "19.0-stag", "19.0")] == ["desarrollo", "staging", "produccion"])
check("las ramas ajenas a integración se ignoran", webhook.environment_for_branch("refs/heads/feat/prueba") is None)

dev_sha = commit_for(work, "19.0-dev")
status, result = send("19.0-dev", dev_sha, "dev-1")
check("HMAC válido publica el candidato de desarrollo", status == 200 and result.get("environment") == "desarrollo")
dev_candidate = candidates / "desarrollo" / "ventas"
check("el candidato contiene el commit recibido", (dev_candidate / ".candidate-commit").read_text().strip() == dev_sha)
bare_before_bad_signature = sorted(path.name for path in bare.iterdir())
check("un HMAC incorrecto se rechaza antes de operar Git", send("19.0-dev", dev_sha, "bad-signature", key=b"z" * 32)[0] == 401 and sorted(path.name for path in bare.iterdir()) == bare_before_bad_signature)
check("un evento distinto de push no cambia candidatos", send("19.0-dev", dev_sha, "ping-1", event="ping")[0] == 202)
check("una rama feat se ignora", send("feat/prueba", dev_sha, "feat-1")[0] == 202)
check("una línea Odoo distinta se ignora", send("20.0-dev", dev_sha, "version-1")[0] == 202)
check("un repositorio ausente del catálogo se ignora", send("19.0-dev", dev_sha, "unknown-1", url=temporary / "desconocido.git")[0] == 202)
check("un evento del repositorio Enterprise se ignora", send("19.0-dev", dev_sha, "enterprise-1", url=temporary / "enterprise.git")[0] == 202 and not (candidates / "desarrollo" / "enterprise").exists())

run("git", "-C", str(work), "checkout", "-q", "19.0-dev")
with (work / "__manifest__.py").open("a") as output:
    output.write("v2\n")
run("git", "-C", str(work), "commit", "-qam", "dev v2")
run("git", "-C", str(work), "checkout", "-q", "19.0")
new_dev_sha = commit_for(work, "19.0-dev")
status, result = send("19.0-dev", new_dev_sha, "dev-1")
check("una entrega repetida es idempotente", status == 200 and result.get("status") == "duplicate")
check("el reintento no reemplaza el commit ya publicado", (dev_candidate / ".candidate-commit").read_text().strip() == dev_sha)
check("una entrega nueva publica el commit actualizado", send("19.0-dev", new_dev_sha, "dev-2")[0] == 200 and (dev_candidate / ".candidate-commit").read_text().strip() == new_dev_sha)
stage_sha = commit_for(work, "19.0-stag")
prod_sha = commit_for(work, "19.0")
check("staging publica solo bajo su ruta", send("19.0-stag", stage_sha, "stage-1")[0] == 200 and (candidates / "staging" / "ventas" / ".candidate-commit").read_text().strip() == stage_sha)
check("producción publica solo bajo su ruta", send("19.0", prod_sha, "prod-1")[0] == 200 and (candidates / "produccion" / "ventas" / ".candidate-commit").read_text().strip() == prod_sha)
check("Odoo activo no recibe cambios por webhook", active_odoo.read_bytes() == active_before)

active = 0
maximum = 0
counter_lock = threading.Lock()
original_sync = webhook.sync_candidate
def measured_sync(entry, branch, environment, config):
    global active, maximum
    with counter_lock:
        active += 1
        maximum = max(maximum, active)
    time.sleep(0.15)
    with counter_lock:
        active -= 1
    return "a" * 40
webhook.sync_candidate = measured_sync
try:
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda args: send("19.0-dev", "a" * 40, *args), (("concurrent-1", remote), ("concurrent-2", remote_two))))
finally:
    webhook.sync_candidate = original_sync
check("entregas simultáneas del mismo entorno se serializan", maximum == 1 and all(status == 200 for status, _ in results))
check("el receptor no altera la referencia de Odoo durante la serie", active_odoo.read_bytes() == active_before)
print(f"\n{checks - failures} ok · {failures} fallas")
sys.exit(0 if failures == 0 else 1)
PY
PY_STATUS=$?

resumen || exit 1
[ "$PY_STATUS" -eq 0 ]
