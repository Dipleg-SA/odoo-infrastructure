# Crear módulo

## Cuándo se usa

Ya tenés un repositorio declarado y sincronizado (ver [crear-fork](crear-fork.md)) y necesitás un módulo nuevo adentro. Es el mismo procedimiento sin importar el origen del repositorio contenedor — un módulo nuevo dentro de tu propio repo o dentro de un fork de terceros nace igual.

No aplica a Odoo Enterprise sin acceso git — ver [crear-enterprise](crear-enterprise.md).

## Objetivo

Módulo scaffoldeado, instalado y corriendo en tu entorno de desarrollo.

## A mano

Decidir el nombre técnico (`snake_case`). Tenelo presente contra la precedencia entre categorías si otro módulo en otra categoría ya usa ese nombre (ver la nota al final de [crear-fork](crear-fork.md)).

## Comandos

```bash
cd addons/<categoría>/<repo> && git checkout -b feat/<nombre-del-modulo> && cd -
```

```bash
docker compose run --rm \
  -v "$PWD/addons:/scaffold" -u "$(id -u):$(id -g)" \
  --entrypoint odoo odoo scaffold <nombre_tecnico> /scaffold/<categoría>/<repo>
```

Tres partes, y ninguna es opcional:

- **`--entrypoint odoo`** — sin él, `docker/odoo/entrypoint.sh` intercepta cualquier argumento asumiendo que es un flag de instalación (`-i`/`-u`) y le antepone `-c/-d/--db_host`, que rompe el `scaffold` (no toca la base).
- **`-v "$PWD/addons:/scaffold"`** — el servicio monta `./addons` en `/mnt/extra-addons` **read-only** (`compose.odoo.yaml`), a propósito: en operación normal Odoo nunca escribe en los addons. Scaffoldear ahí falla con `OSError: [Errno 30] Read-only file system`. Este segundo mount del mismo directorio, en modo escritura, es solo para este comando.
- **`-u "$(id -u):$(id -g)"`** — sin él, los archivos quedan con el owner del usuario del contenedor y no vas a poder commitearlos desde el host sin `chown`.

```bash
make odoo-install MODULES=<nombre_tecnico>
```

## Verificación

```bash
make odoo-modules   # <nombre_tecnico> aparece instalado
make addons         # el repo está en feat/<nombre-del-modulo>, limpio
```

---

De acá en más, cualquier cambio a este módulo —incluida la primera vez que se instala en staging o en producción— sigue [actualizar-modulo](actualizar-modulo.md).
