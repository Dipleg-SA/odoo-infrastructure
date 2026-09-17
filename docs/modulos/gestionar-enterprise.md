# Gestionar Enterprise

## Cuándo se usa

Cuando el runtime selecciona `ODOO_EDITION=enterprise`. Enterprise se mantiene en un
checkout privado fuera del repositorio de infraestructura y se selecciona por un tag
anotado e inmutable de la misma línea de Odoo.

## Objetivo

Dejar disponible el checkout privado en `runtime/addons/enterprise/`, validarlo contra
`TAG` y construir una imagen Enterprise reproducible. El repositorio público no guarda
el código, sus credenciales ni sus artefactos.

## Flujo rápido

1. Prepará o actualizá manualmente el checkout privado de Enterprise en
   `runtime/addons/enterprise/` y seleccioná un tag `19.0-ee-YYYY-MM-DD`.
2. Validá el checkout y resolvé dependencias Python si corresponde:

   ```bash
   ENTORNO=desarrollo scripts/addons.sh enterprise-sync <url-privada> <tag>
   ENTORNO=desarrollo scripts/addons.sh enterprise-validate <tag>
   ENTORNO=desarrollo make addons-deps
   ENTORNO=desarrollo make build
   ```

3. Validá la imagen y las operaciones funcionales manualmente en desarrollo y staging.
4. Repetí la selección del mismo tag en el checkout privado de cada entorno; no copies
   código ni credenciales al repositorio público.
5. En producción, conservá el backup requerido y aplicá la imagen solo después de la
   validación de staging:

   ```bash
   ENTORNO=produccion make build
   ENTORNO=produccion make validate-image NOTE="staging aprobado"
   ENTORNO=produccion make apply-image
   ```

| Situación | Comando |
| --- | --- |
| Seleccionar el checkout privado | `ENTORNO=<entorno> scripts/addons.sh enterprise-sync <url> <tag>` |
| Validar tag, commit y limpieza | `ENTORNO=<entorno> scripts/addons.sh enterprise-validate <tag>` |
| Resolver dependencias declaradas | `ENTORNO=<entorno> make addons-deps` |
| Construir la fotografía | `ENTORNO=<entorno> make build` |
| Verificar el runtime | `ENTORNO=<entorno> make verify` |

## A mano

El acceso al repositorio privado, la selección del tag y la validación funcional son
responsabilidad del operador. No se automatiza la instalación, actualización,
desinstalación ni validación funcional de módulos.

## Contrato de edición

Enterprise usa únicamente este par en el archivo privado del runtime:

```ini
ODOO_EDITION=enterprise
TAG=19.0-ee-YYYY-MM-DD
```

Community usa `ODOO_EDITION=community` y `TAG=19.0-ce-YYYY-MM-DD`; no necesita
checkout Enterprise. No se interpretan bloques `[enterprise]` o `[community]` ni se
mantiene un archivo adicional de selección.

## Verificación

```bash
ENTORNO=desarrollo scripts/addons.sh enterprise-validate "$TAG"
ENTORNO=desarrollo make verify
ENTORNO=staging make verify
ENTORNO=produccion make verify
```

La verificación debe confirmar que el commit coincide con el tag, que el checkout está
limpio y que `images.json` conserva `edition`, `edition_tag`, `enterprise_tag` y
`enterprise_commit`. El código Enterprise no se versiona ni se publica mediante
webhook.

## Retirar Enterprise y pasar a Community

No retires el checkout Enterprise antes de quitar manualmente sus módulos de la base.
Primero restaurá una copia en staging, comprobá el inventario y desinstalá los módulos
afectados mediante el procedimiento de módulos. Después cambiá únicamente:

```ini
ODOO_EDITION=community
TAG=19.0-ce-YYYY-MM-DD
```

Construí y validá la imagen Community en staging. `apply-image` vuelve a ejecutar el
preflight en producción, exige el backup asociado y no convierte módulos por sí solo.
Si la base todavía conserva módulos Enterprise, la transición queda bloqueada.
