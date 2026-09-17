# Gestionar un fork de addons

## Cuándo se usa

Para incorporar, actualizar o retirar un repositorio propio o forkeado de terceros del catálogo de addons.

## Objetivo

Mantener un repositorio por dominio, declarado en `runtime/addons/catalogo.txt`, con ramas `feat/*`, `19.0-stag` y `19.0`. Desarrollo inicializa su feature desde producción; el servidor solo recibe candidatos de staging y producción.

## Flujo rápido

1. Crear o forkear el repositorio en la organización propia y declararlo en el catálogo.
2. Trabajar y probar los cambios en `feat/<nombre>` local.
3. Integrar la feature o una actualización externa en `19.0-stag`, validar el conjunto en staging y registrar la evidencia.
4. Promover el conjunto completo mediante PR `19.0-stag → 19.0`; luego sincronizar y verificar producción antes del build.

## A mano

Los forks de terceros conservan `upstream` además de `origin`. Desarrollo puede inicializar una `feat/*` con su credencial acotada; staging y producción no modifican Git y sus credenciales son de solo lectura. Los conflictos de una actualización externa se resuelven antes de publicar `19.0-stag`.

`19.0-stag` puede tener varias features. Un PR de promoción incluye todo su delta contra `19.0`, no solo el último cambio. Si el conjunto deja de ser útil, realineá staging con producción según [gestionar ramas de staging](gestionar-ramas-staging.md); no se usa rebase para nombrar esa operación.

## Comandos

Incorporar un repositorio propio o un fork:

```bash
$EDITOR runtime/addons/catalogo.txt
ENTORNO=desarrollo make repo-sync
```

Cambiar la feature declarada en desarrollo:

```bash
$EDITOR runtime/desarrollo/compose.env
# ADDONS_REF=feat/mi-cambio
ENTORNO=desarrollo make repo-sync
```

Traer una actualización de un fork de terceros y prepararla para staging:

```bash
git fetch upstream --prune
git switch 19.0-stag
git pull --ff-only origin 19.0-stag
git merge upstream/19.0
git push origin 19.0-stag
```

Si hay conflictos, resolvelos y probalos localmente antes del push. En staging, sincronizá y validá el conjunto completo:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
ENTORNO=staging make apply-image
ENTORNO=staging make validate-image NOTE="validación del conjunto 19.0-stag"
ENTORNO=staging make verify
```

Después de aprobar y fusionar el PR `19.0-stag → 19.0`:

```bash
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
```

`promotion-verify` debe terminar bien antes de aplicar la imagen productiva. La instalación, actualización o desinstalación de módulos sigue siendo manual y se realiza solo después de preservar el backup requerido.

Retirar un repositorio:

```bash
ENTORNO=<entorno> make addons-uninstall MODULES=<modulos>
$EDITOR runtime/addons/catalogo.txt
ENTORNO=<entorno> make repo-status
```

Repetí la desinstalación y el retiro del catálogo en cada entorno que tenga módulos instalados. Los candidatos huérfanos se conservan visibles para limpieza manual; no se eliminan automáticamente.

## Verificación

En staging, `repo-status` debe mostrar los candidatos de `19.0-stag` y `images.json` debe registrar una `Actual` con `validation.result: ok`. Tras el PR, `ENTORNO=produccion make promotion-verify` debe confirmar árboles de addons, edición y procedencia Enterprise equivalentes antes del build productivo.
