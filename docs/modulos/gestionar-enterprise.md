# Gestionar Enterprise

## Cuándo se usa

Módulo de Odoo Enterprise, sin acceso al repositorio privado de GitHub — se consume vía el ZIP que se descarga desde el portal de tu cuenta. Es la excepción al resto del modelo de addons: la licencia no permite forkear el código a una organización propia, así que no hay fork, rama Git de staging ni `repo-sync`.

El mismo procedimiento sirve para instalar el módulo por primera vez y para traer una versión nueva más adelante — no hay git de por medio, así que "crear" y "actualizar" son literalmente el mismo comando.

## Objetivo

Módulo disponible en `addons/enterprise/`, instalado.

## Flujo rápido

Este es el recorrido para instalar un módulo Enterprise por primera vez o actualizarlo con un ZIP nuevo. El ZIP se aplica manualmente en cada checkout; no viaja por Git.

1. **Descargar el ZIP** de la misma versión de Odoo que usa el entorno. No hay comando `make` en esta etapa.

2. **Descomprimirlo en desarrollo** y resolver dependencias Python si el módulo las declara:

   ```bash
   unzip -q odoo-enterprise.zip -d addons/enterprise/
   make addons-deps
   make build   # solo si addons-deps agregó o cambió pines
   ```

3. **Instalar o actualizar en desarrollo** según el estado de la base:

   ```bash
   make addons-install MODULES=<nombre_tecnico>  # primera vez en esta base
   # o
   make addons-update MODULES=<nombre_tecnico>   # ya estaba instalado
   make odoo-verify
   ```

4. **Repetir el mismo ZIP en staging** y validar antes de producción:

   ```bash
   unzip -q odoo-enterprise.zip -d addons/enterprise/
   make addons-deps
   make build   # solo si addons-deps agregó o cambió pines
   make addons-install MODULES=<nombre_tecnico>  # primera vez en staging
   # o
   make addons-update MODULES=<nombre_tecnico>   # ya estaba instalado
   make verify
   ```

5. **Aplicar el ZIP validado en producción** y confirmar el resultado:

   ```bash
   unzip -q odoo-enterprise.zip -d addons/enterprise/
   make addons-deps
   make build   # solo si addons-deps agregó o cambió pines
   make addons-install MODULES=<nombre_tecnico>  # primera vez en producción
   # o
   make addons-update MODULES=<nombre_tecnico>   # ya estaba instalado
   make verify
   make addons-modules
   ```

| Situación | Comando |
| --- | --- |
| Primera instalación en una base | `make addons-install MODULES=<nombre_tecnico>` |
| Módulo ya instalado en la base | `make addons-update MODULES=<nombre_tecnico>` |
| El módulo declaró dependencias Python | `make addons-deps` y, si agregó pines, `make build` |
| Validar el entorno tras instalar o actualizar | `make odoo-verify` en desarrollo; `make verify` en staging o producción |

## A mano

Descargar el ZIP desde el portal de tu cuenta de Odoo.

## Comandos

```bash
unzip -q odoo-enterprise.zip -d addons/enterprise/
make addons-deps
make build   # solo si addons-deps agregó o cambió pines
```

`entrypoint.sh` arma el `addons_path` con un glob por categoría. El ZIP debe conservar su directorio contenedor de primer nivel dentro de `addons/enterprise/`; los módulos son los directorios que contienen `__manifest__.py`, no necesariamente los directorios de primer nivel.

Después elegí **uno** de estos comandos, nunca los dos:

```bash
make addons-install MODULES=<nombre_tecnico>   # primera vez en esta base
```

```bash
make addons-update MODULES=<nombre_tecnico>    # el módulo ya estaba instalado
```

## Verificación

### Desarrollo

```bash
find addons/enterprise -name __manifest__.py -print
make addons-modules
make odoo-verify
docker compose logs --since 5m odoo
```

Confirmá que el módulo figura instalado y probá en la UI local el flujo que agrega o modifica. Si tocaste vistas o datos, recargá sin caché. Si el ZIP agregó una dependencia Python, comprobá `make addons-deps` y reconstruí la imagen cuando haya cambiado algún pin.

### Staging

```bash
make addons-modules
docker compose logs --since 5m odoo
make verify
```

Probá el flujo con los datos restaurados de producción y revisá los cambios sobre registros existentes. Confirmá que no salió correo real: staging fuerza `ODOO_DISABLE_SMTP=1`. No copies el ZIP a producción hasta completar esta validación.

### Producción

```bash
make addons-modules
docker compose logs --since 10m odoo
make verify
```

Probá el flujo con cuidado y confirmá que llegó el correo si el cambio lo dispara. Esta comprobación es de confirmación; la prueba exploratoria ya se hizo en staging. Si falla algo que pasó allí, registrá el caso y ampliá la validación de staging para la próxima actualización.

---

**Sin staging por git.** Sin `repo-sync` no hay forma de traer este cambio al servidor de staging antes de producción por el camino habitual. Si querés probarlo antes de tocar producción, repetí este mismo `unzip` + `addons-install`/`addons-update` a mano en el checkout de staging primero — es la única forma de validarlo con este mecanismo.

La carpeta sigue gitignoreada por dentro, igual que cualquier otra categoría: el ZIP nunca se versiona.
