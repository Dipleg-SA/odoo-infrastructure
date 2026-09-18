# Gestionar Enterprise

## Cuándo se usa

Cuando el runtime selecciona `ODOO_EDITION=enterprise`. Enterprise se mantiene en un
checkout privado fuera del repositorio de infraestructura y se selecciona por un tag
anotado e inmutable de la misma línea de Odoo.

## Objetivo

Validar el checkout privado en `runtime/addons/enterprise/` y construir una imagen
Enterprise reproducible. El repositorio público no guarda el código, sus credenciales ni
sus artefactos.

## Flujo rápido

1. Preparar el checkout privado y seleccionar un tag `19.0-ee-YYYY-MM-DD`.
2. Validar el tag y resolver dependencias.
3. Construir, levantar y verificar la imagen en desarrollo y staging.
4. Repetir el mismo tag en producción después del backup y la aprobación de staging.

```bash
ENTORNO=desarrollo scripts/addons.sh enterprise-sync <url-privada> <tag>
ENTORNO=desarrollo scripts/addons.sh enterprise-validate <tag>
ENTORNO=desarrollo make addons-deps
ENTORNO=desarrollo make build
ENTORNO=desarrollo make odoo-up
ENTORNO=desarrollo make verify
```

| Situación | Comando |
| --- | --- |
| Seleccionar el checkout privado | `ENTORNO=<entorno> scripts/addons.sh enterprise-sync <url> <tag>` |
| Validar tag, commit y limpieza | `ENTORNO=<entorno> scripts/addons.sh enterprise-validate <tag>` |
| Resolver dependencias declaradas | `ENTORNO=<entorno> make addons-deps` |
| Construir la imagen | `ENTORNO=<entorno> make build` |
| Verificar el runtime | `ENTORNO=<entorno> make verify` |

## Contrato de edición

```ini
ODOO_EDITION=enterprise
TAG=19.0-ee-YYYY-MM-DD
```

Community usa `ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`; no necesita
checkout Enterprise. No se interpretan bloques alternativos ni un archivo adicional de
selección.

## Verificación

```bash
ENTORNO=desarrollo scripts/addons.sh enterprise-validate "$TAG"
ENTORNO=desarrollo make odoo-verify
ENTORNO=staging make verify
ENTORNO=produccion make verify
```

La verificación confirma que el commit coincide con el tag, que el checkout está limpio,
que la imagen seleccionada corresponde a Enterprise y que su metadata conserva la
procedencia. El código Enterprise no se versiona ni se publica mediante webhook.

## Retirar Enterprise y pasar a Community

No retires el checkout Enterprise antes de quitar manualmente sus módulos de la base.
Restaurá una copia en staging, comprobá el inventario y desinstalá los módulos afectados.
Después cambiá únicamente:

```ini
ODOO_EDITION=community
TAG=19.0-ce-YYYY-MM-DD
```

Construí y validá la imagen Community en staging. En producción conservá el backup,
construí de nuevo y verificá que la base no conserve módulos Enterprise.
