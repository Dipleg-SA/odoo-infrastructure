# Gestionar un fork de addons

## Cuándo se usa

Para incorporar, actualizar o retirar un repositorio propio o forkeado de terceros del
catálogo de addons.

## Objetivo

Mantener un repositorio por dominio, declarado en `runtime/addons/catalogo.txt`, con
ramas `feat/*`, `19.0-stag` y `19.0`. Desarrollo inicializa su feature desde producción;
el servidor solo recibe candidatos de staging y producción.

## Flujo rápido

1. Crear o forkear el repositorio y declararlo en el catálogo.
2. Trabajar y probar los cambios en `feat/<nombre>` local.
3. Integrar la feature en `19.0-stag`, construir y validar el conjunto en staging.
4. Promover el conjunto completo por PR `19.0-stag → 19.0` y verificar producción.

## A mano

Los forks de terceros conservan `upstream` además de `origin`. Desarrollo puede
inicializar una `feat/*`; staging y producción no modifican Git y usan credenciales de
solo lectura. Los conflictos se resuelven antes de publicar `19.0-stag`.

## Comandos

Incorporar un repositorio propio o un fork:

```bash
$EDITOR runtime/addons/catalogo.txt
ENTORNO=desarrollo make repo-sync
```

Traer una actualización externa:

```bash
git fetch upstream --prune
git switch 19.0-stag
git pull --ff-only origin 19.0-stag
git merge upstream/19.0
git push origin 19.0-stag
```

En staging, sincronizá, construí y validá el conjunto completo:

```bash
ENTORNO=staging make repo-sync
ENTORNO=staging make addons-deps
ENTORNO=staging make build
ENTORNO=staging make odoo-up
ENTORNO=staging make verify
```

Después de aprobar y fusionar el PR:

```bash
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
ENTORNO=produccion make odoo-up
```

La instalación, actualización o desinstalación de módulos sigue siendo manual y se
realiza solo después de preservar el backup requerido.

Retirar un repositorio:

```bash
ENTORNO=<entorno> make addons-uninstall MODULES=<modulos>
$EDITOR runtime/addons/catalogo.txt
ENTORNO=<entorno> make repo-status
```

Repetí el retiro en cada entorno que tenga módulos instalados. Los candidatos huérfanos
se conservan visibles para limpieza manual.

## Verificación

`repo-status` debe mostrar los candidatos esperados de `19.0-stag`. Después del PR,
`ENTORNO=produccion make promotion-verify` debe confirmar árboles de addons, edición y
procedencia Enterprise equivalentes antes del build productivo.
