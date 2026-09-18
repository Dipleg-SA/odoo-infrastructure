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
for entorno in desarrollo staging produccion; do
  contiene "el receptor monta custom de $entorno" "/runtime/$entorno/addons/custom" "$PROD"
  contiene "el receptor separa el destino $entorno" "target: /var/lib/addons/$entorno" "$PROD"
done
no_contiene "el receptor no monta Enterprise" "/addons/enterprise" \
  "$(printf '%s\n' "$PROD" | sed -n '/^  addons-webhook:/,/^  [a-z0-9_-]*:$/p')"

# Verificación del stack
# La fixture devuelve la composición real y simula el servicio detenido.
mkdir -p "$TMP/verify"
: > "$TMP/verify/ps-q"
: > "$TMP/verify/ps"
: > "$TMP/verify/port"
: > "$TMP/verify/salida"
printf '%s\n' addons-webhook > "$TMP/verify/servicios"
printf '%s\n' addons-webhook > "$TMP/verify/servicios-sin-perfil"
cp runtime/produccion/compose.env.example "$TMP/verify/config.env"
STUB_DIR="$TMP/verify" docker compose --env-file runtime/produccion/compose.env.example \
  -f runtime/produccion/compose.yaml config > "$TMP/verify/config"
cp "$TMP/verify/config" "$TMP/verify/config-valida"
SALIDA=$(STUB_DIR="$TMP/verify" PATH="$PWD/tests/stubs:$PATH" ENTORNO=produccion \
  scripts/verify-stacks.sh addons-webhook 2>&1 || true)
contiene "el stack con guion se descubre y ejecuta" "addons-webhook" "$SALIDA"
contiene "el verify acepta las rutas limitadas de secretos" \
  "solo monta los cuatro secretos dedicados al webhook" "$SALIDA"
contiene "el verify exige usuario no privilegiado" \
  "receptor no privilegiado y filesystem de imagen inmutable" "$SALIDA"
no_contiene "el verify no confunde el nombre del checkout con Odoo" \
  "la composición del receptor contiene una referencia prohibida" "$SALIDA"
for entorno in desarrollo staging produccion; do
  contiene "el verify valida el destino custom de $entorno" \
    "destino custom de $entorno limitado" "$SALIDA"
done

# Mutaciones de mounts
# El verificador del stack debe rechazar ausencia, Enterprise y creación implícita.
sed '/source: .*runtime\/staging\/addons\/custom/,+4d' \
  "$TMP/verify/config-valida" > "$TMP/verify/config"
SALIDA=$(STUB_DIR="$TMP/verify" PATH="$PWD/tests/stubs:$PATH" ENTORNO=produccion \
  scripts/verify-stacks.sh addons-webhook 2>&1 || true)
contiene "el verify detecta un destino faltante" \
  "✗ destino custom de staging limitado" "$SALIDA"

sed 's@target: /var/lib/addons/staging@target: /var/lib/addons/enterprise@' \
  "$TMP/verify/config-valida" > "$TMP/verify/config"
SALIDA=$(STUB_DIR="$TMP/verify" PATH="$PWD/tests/stubs:$PATH" ENTORNO=produccion \
  scripts/verify-stacks.sh addons-webhook 2>&1 || true)
contiene "el verify detecta un mount Enterprise" \
  "la composición del receptor contiene una referencia prohibida" "$SALIDA"

sed '/source: .*runtime\/staging\/addons\/custom/,+4 s/create_host_path: false/create_host_path: true/' \
  "$TMP/verify/config-valida" > "$TMP/verify/config"
SALIDA=$(STUB_DIR="$TMP/verify" PATH="$PWD/tests/stubs:$PATH" ENTORNO=produccion \
  scripts/verify-stacks.sh addons-webhook 2>&1 || true)
contiene "el verify detecta creación implícita" \
  "✗ destino custom de staging limitado" "$SALIDA"

# Targets del contenedor
# El receptor usa el mismo sexteto Make que los demás stacks.
TARGETS=$(make -qp 2>/dev/null)
for target in addons-webhook-up addons-webhook-down addons-webhook-restart \
  addons-webhook-logs addons-webhook-ps addons-webhook-verify; do
  contiene "Make registra $target" "${target}:" "$TARGETS"
done
TARGET_UP=$(make -n ENTORNO=produccion addons-webhook-up 2>&1 || true)
contiene "addons-webhook-up ejecuta el bootstrap de mounts" \
  "scripts/addons-runtime.sh init" "$TARGET_UP"

sed 's@target: /var/lib/addons-webhook@target: /var/run/docker.sock@' \
  "$TMP/verify/config-valida" > "$TMP/verify/config-insegura"
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
environment_config = webhook.Config.from_env()
check("Config funciona desde el WORKDIR /app del contenedor", environment_config.catalog_path == environment_paths["ADDONS_CATALOG"])
check("Config usa la raíz explícita de destinos", environment_config.candidate_root == environment_paths["ADDONS_CANDIDATE_ROOT"])
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
    for branch, content in (("19.0-stag", "staging"),):
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

check("las dos ramas de servidor se asignan a su entorno", [webhook.environment_for_branch(f"refs/heads/{b}")[0] for b in ("19.0-stag", "19.0")] == ["staging", "produccion"])
check("las ramas de desarrollo se ignoran", webhook.environment_for_branch("refs/heads/19.0-dev") is None and webhook.environment_for_branch("refs/heads/feat/prueba") is None)

stage_sha = commit_for(work, "19.0-stag")
bare_before_bad_signature = sorted(path.name for path in bare.iterdir()) if bare.exists() else []
check("un HMAC incorrecto se rechaza antes de operar Git", send("19.0-stag", stage_sha, "bad-signature", key=b"z" * 32)[0] == 401 and (sorted(path.name for path in bare.iterdir()) if bare.exists() else []) == bare_before_bad_signature)
check("un evento distinto de push no cambia candidatos", send("19.0-stag", stage_sha, "ping-1", event="ping")[0] == 202)
check("una rama de desarrollo se ignora sin publicar candidatos", send("19.0-dev", stage_sha, "dev-1")[0] == 202 and not (candidates / "desarrollo").exists())
check("una rama feat se ignora", send("feat/prueba", stage_sha, "feat-1")[0] == 202)
check("una línea Odoo distinta se ignora", send("20.0-stag", stage_sha, "version-1")[0] == 202)
check("un repositorio ausente del catálogo se ignora", send("19.0-stag", stage_sha, "unknown-1", url=temporary / "desconocido.git")[0] == 202)
check("un evento del repositorio Enterprise se ignora", send("19.0-stag", stage_sha, "enterprise-1", url=temporary / "enterprise.git")[0] == 202 and not (candidates / "staging" / "enterprise").exists())

observed_commands = []
original_subprocess_run = webhook.subprocess.run
def observed_run(arguments, *args, **kwargs):
    observed_commands.append([str(value) for value in arguments])
    return original_subprocess_run(arguments, *args, **kwargs)
webhook.subprocess.run = observed_run
try:
    status, result = send("19.0-stag", stage_sha, "stage-1")
finally:
    webhook.subprocess.run = original_subprocess_run
stage_candidate = candidates / "staging" / "ventas"
check("HMAC válido publica el candidato de staging", status == 200 and result.get("environment") == "staging")
check("el webhook no construye imágenes", observed_commands and all(command[0] == "git" and "build" not in command for command in observed_commands))
check("el webhook no recrea ni reinicia Odoo", all(not ({"up", "restart", "compose"} & set(command)) for command in observed_commands))
check("el webhook no instala, actualiza ni desinstala módulos", all(not ({"install", "update", "uninstall", "-i", "-u"} & set(command)) for command in observed_commands))
check("el candidato contiene el commit recibido", (stage_candidate / ".candidate-commit").read_text().strip() == stage_sha)
expected_tree = subprocess.check_output(["git", "-C", str(work), "rev-parse", f"{stage_sha}^{{tree}}"], text=True).strip()
check("el candidato contiene el árbol Git recibido", (stage_candidate / ".candidate-tree").read_text().strip() == expected_tree)
check("staging no publica en otros entornos", not (candidates / "desarrollo" / "ventas").exists() and not (candidates / "produccion" / "ventas").exists())
run("git", "-C", str(work), "checkout", "-q", "19.0-stag")
with (work / "__manifest__.py").open("a") as output:
    output.write("v2\n")
run("git", "-C", str(work), "commit", "-qam", "staging v2")
run("git", "-C", str(work), "checkout", "-q", "19.0")
new_stage_sha = commit_for(work, "19.0-stag")
status, result = send("19.0-stag", new_stage_sha, "stage-1")
check("una entrega repetida es idempotente", status == 200 and result.get("status") == "duplicate")
check("el reintento no reemplaza el commit ya publicado", (stage_candidate / ".candidate-commit").read_text().strip() == stage_sha)
check("una entrega nueva publica el commit actualizado", send("19.0-stag", new_stage_sha, "stage-2")[0] == 200 and (stage_candidate / ".candidate-commit").read_text().strip() == new_stage_sha)
prod_sha = commit_for(work, "19.0")
check("producción publica solo bajo su ruta", send("19.0", prod_sha, "prod-1")[0] == 200 and (candidates / "produccion" / "ventas" / ".candidate-commit").read_text().strip() == prod_sha)
check("producción no reemplaza staging", (stage_candidate / ".candidate-commit").read_text().strip() == new_stage_sha)
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
        results = list(pool.map(lambda args: send("19.0-stag", "a" * 40, *args), (("concurrent-1", remote), ("concurrent-2", remote_two))))
finally:
    webhook.sync_candidate = original_sync
check("entregas simultáneas del mismo entorno se serializan", maximum == 1 and all(status == 200 for status, _ in results))
check("el receptor no altera la referencia de Odoo durante la serie", active_odoo.read_bytes() == active_before)

# Contención con una operación funcional
# El lock Bash de módulos y el lock Python del webhook deben ser el mismo inode lógico.
run("git", "-C", str(work), "checkout", "-q", "19.0-stag")
with (work / "__manifest__.py").open("a") as output:
    output.write("v3\n")
run("git", "-C", str(work), "commit", "-qam", "staging v3")
run("git", "-C", str(work), "checkout", "-q", "19.0")
third_stage_sha = commit_for(work, "19.0-stag")
held = temporary / "module-lock-held"
release = temporary / "module-lock-release"
holder_code = (
    "import pathlib,time,sys; "
    "held=pathlib.Path(sys.argv[1]); release=pathlib.Path(sys.argv[2]); "
    "held.write_text('held'); "
    "[(time.sleep(0.01)) for _ in iter(lambda: release.exists(), True)]"
)
holder_environment = os.environ.copy()
holder_environment["ADDONS_STATE_DIR"] = str(state)
holder = subprocess.Popen(
    ["bash", str(root / "scripts/lib/candidate-lock.sh"), "run", "staging", "--",
     sys.executable, "-c", holder_code, str(held), str(release)],
    env=holder_environment,
)
for _ in range(200):
    if held.exists():
        break
    time.sleep(0.01)
before_locked_publish = (stage_candidate / ".candidate-commit").read_text().strip()
with ThreadPoolExecutor(max_workers=1) as pool:
    pending = pool.submit(send, "19.0-stag", third_stage_sha, "module-contention")
    time.sleep(0.1)
    check("el webhook espera mientras una operación de módulo conserva el lock", not pending.done())
    check("el árbol no cambia durante la operación funcional", (stage_candidate / ".candidate-commit").read_text().strip() == before_locked_publish)
    release.write_text("release")
    locked_result = pending.result(timeout=10)
holder.wait(timeout=10)
check("el candidato se publica después de liberar la operación", locked_result[0] == 200 and (stage_candidate / ".candidate-commit").read_text().strip() == third_stage_sha)
print(f"\n{checks - failures} ok · {failures} fallas")
sys.exit(0 if failures == 0 else 1)
PY
PY_STATUS=$?

resumen || exit 1
[ "$PY_STATUS" -eq 0 ]
