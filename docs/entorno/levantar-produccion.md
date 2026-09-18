# Levantar producción

## Cuándo se usa

Para preparar o recuperar el runtime productivo de una línea mayor de Odoo.

## Objetivo

Producción ejecuta la única imagen Odoo declarada y monta
`runtime/produccion/addons/{custom,enterprise}` como solo lectura. Conserva backup de
base y filestore y opera con `ENTORNO=produccion` explícito.

## Preparación

Después de fusionar el PR `19.0-stag → 19.0`:

```bash
cp runtime/produccion/compose.env.example runtime/produccion/compose.env
cp runtime/addons/catalogo.txt.example runtime/addons/catalogo.txt
cp runtime/addons/requirements.override.txt.example runtime/addons/requirements.override.txt

ENTORNO=produccion make secrets-init config-init
sudo ENTORNO=produccion make secrets-perms
ENTORNO=produccion make secrets-check
ENTORNO=produccion make host-verify
ENTORNO=produccion make cert-issue
ENTORNO=produccion make addons-runtime-init
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
ENTORNO=produccion make addons-deps
ENTORNO=produccion make build
```

`make build` actualiza `ODOO_IMAGE` solo después de construir y verificar la identidad
Docker. Es obligatorio en el bootstrap o si cambian `odoo_base`, edición o dependencias;
un commit nuevo con las mismas huellas conserva la imagen.

El flujo frecuente posterior al PR es:

```bash
ENTORNO=produccion make repo-sync
ENTORNO=produccion make promotion-verify
ENTORNO=produccion make addons-deps
ENTORNO=produccion make backup-run
ENTORNO=produccion make odoo-restart
ENTORNO=produccion make odoo-verify
```

`promotion-verify` compara `19.0` con la selección que staging tiene cargada. Si el
preflight de la recreación exige una imagen nueva, ejecutá `make build` antes de
`odoo-restart`. Las operaciones de módulos siguen siendo explícitas y posteriores.

## Flujo por stacks

### 1. Edge

```bash
ENTORNO=produccion make nginx-up
ENTORNO=produccion make nginx-verify
ENTORNO=produccion make cloudflared-up
ENTORNO=produccion make cloudflared-verify
```

Si la instalación usa DNS local, sumá el perfil explícito:

```bash
COMPOSE_PROFILES=lan ENTORNO=produccion make dnsmasq-up
COMPOSE_PROFILES=lan ENTORNO=produccion make dnsmasq-verify
```

### 2. PostgreSQL

```bash
ENTORNO=produccion make postgres-up
ENTORNO=produccion make postgres-verify
```

No continúes si `postgres-verify` falla.

### 3. Odoo

```bash
ENTORNO=produccion make odoo-up
ENTORNO=produccion make odoo-verify
```

`odoo-up` valida que `ODOO_IMAGE` sea explícita, local y correspondiente al entorno antes de crear el contenedor.

### 4. Backup

```bash
ENTORNO=produccion make backup-up
ENTORNO=produccion make backup-verify
ENTORNO=produccion make backup-run
sudo ENTORNO=produccion make up-timers
```

El backup conserva base, filestore y la selección de addons cargada por el contenedor,
además de la metadata del snapshot. No selecciona ni restaura imágenes.

### 5. Monitoring

```bash
ENTORNO=produccion make prometheus-up
ENTORNO=produccion make prometheus-verify
ENTORNO=produccion make loki-up
ENTORNO=produccion make loki-verify
ENTORNO=produccion make grafana-up
ENTORNO=produccion make grafana-verify
ENTORNO=produccion make alloy-up
ENTORNO=produccion make alloy-verify
```

## Cambios de edición y recuperación

Para Community→Enterprise, ejecutá el preflight de solo lectura contra la base vigente, cambiá `ODOO_EDITION`/`TAG`, construí la imagen y verificá el runtime. No se instalan módulos automáticamente.

Ante una pérdida, restaurá base y filestore desde el snapshot y reconstruí explícitamente la imagen a partir de los candidatos y la edición declarada. La recuperación no depende de estados históricos ni de una selección alternativa.

## Verificación final

```bash
ENTORNO=produccion make verify
```

`promotion-verify` debe terminar correctamente antes del build productivo. La validación funcional de staging es evidencia de código y datos, no una promoción de imagen.

## Verificación aislada sin afectar producción

Para ensayar restore y operación de producción sin reemplazar el stack activo, copiá el checkout a una ruta de verificación y seguí [`verificar-runtime-aislado.md`](verificar-runtime-aislado.md). Usá un snapshot exacto, credenciales autorizadas del entorno y una identidad Compose distinta. La copia no ejecuta `backup-run` ni instala timers; Cloudflare puede quedar fuera de alcance cuando la prueba se limita a aplicación, datos, backup y monitoring.
