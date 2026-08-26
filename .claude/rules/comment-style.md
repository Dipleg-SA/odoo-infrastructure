# Comment style — código y config versionados

Regla oficial (reemplaza cualquier guía ad hoc anterior). Aplica a todo archivo de
código/config versionado en git: `compose.yaml`, `Dockerfile`s, `entrypoint.sh`
y demás scripts, `*.conf`/`*.ini`/`*.yaml` bajo `stacks/` y `envs/`, y el `Makefile`.
No aplica a prosa (`docs/*.md`, `PRINCIPLES.md`, `README.md`) — esos
ya se organizan con sus propios encabezados Markdown.

## Formato

Cada bloque lógico del archivo lleva exactamente dos líneas, con el carácter de
comentario nativo del archivo (`#` en YAML/shell/Postgres, `;` en INI tipo
odoo.conf/grafana.ini):

```
<comment> --- Título ---
<comment> Descripción breve (máx. ~20 palabras).
```

- 1 línea de título + 1 línea de descripción + 1 línea en blanco que separa el
  comentario del código. Nunca más — si la descripción no entra en una línea,
  se recorta, no se envuelve a una segunda línea.
- Se agrupa por bloque funcional (ej. "Workers y límites", "Init check", "Stage 1:
  aggregate addons"), no línea por línea.
- Objetivo: con esas dos líneas de comentario alguien debe entender qué hace el
  bloque y por qué, sin tener que leer el código de abajo.
- Contexto histórico, incidentes pasados o justificaciones largas van a
  `docs/architecture.md`, no inline.

## Ejemplo (`stacks/postgres/config/postgresql.conf`)

```
# --- Tuning ---
# Ratio sobre el cap del contenedor, no sobre la RAM del host.

shared_buffers       = 512MB
effective_cache_size = 1536MB
```

## Ya aplicado en

Los once stacks bajo `stacks/`, los tres entrypoints de `envs/` y el `Makefile`.
