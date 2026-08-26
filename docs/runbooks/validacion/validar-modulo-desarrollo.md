# Validar módulo en desarrollo

## Cuándo se usa

Terminaste (o estás en medio de) el bucle de [crear-modulo](../modulos/crear-modulo.md)/[actualizar-modulo](../modulos/actualizar-modulo.md) en tu entorno local y necesitás confirmar que el módulo hace lo que tiene que hacer antes de gastar un ciclo de staging con él. Es la barrera más barata de las tres — falla rápido y sin tocar nada compartido.

## Objetivo

El módulo instalado sin errores, con el comportamiento esperado probado a mano en tu entorno de desarrollo.

## Comandos

```bash
make odoo-update MODULES=<nombre_tecnico>
```

Revisar los logs de la corrida, no solo el exit code — un `-u` puede terminar con `0` y haber logueado un warning que importa:

```bash
docker compose logs --since 5m odoo | grep -iE 'error|traceback|warn'
```

Confirmar la versión instalada:

```bash
make odoo-modules
```

## Verificación

```bash
make odoo-verify
```

Sirve igual en desarrollo que en cualquier otro entorno — cubre que Odoo responda, los worktrees limpios, y el resto del checklist mecánico.

Lo que `odoo-verify` **no** cubre, porque es específico de tu módulo, va a mano:

- Entrar a `http://127.0.0.1:${HTTP_PORT:-8081}` y probar el flujo real que el cambio agrega o modifica — no solo que la vista carga, sino que la acción que dispara hace lo que tiene que hacer.
- Si el módulo declara `external_dependencies.python`, confirmar que `make pydeps-check` está en verde antes de dar el cambio por probado — un error de import que no aparece en desarrollo porque la librería ya estaba instalada de otra vez sí va a aparecer en un rebuild limpio.
- Si tocaste datos de demo o vistas, recargar sin caché (los assets de Odoo se cachean agresivo) para no confundir un cambio no aplicado con un bug.

---

Con esto en verde, seguí a [validar-modulo-staging](validar-modulo-staging.md) como parte de la integración ([actualizar-modulo](../modulos/actualizar-modulo.md)).
