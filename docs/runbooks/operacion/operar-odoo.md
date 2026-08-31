# Operar odoo

## Cuándo se usa

Necesitás subir, bajar, reiniciar o inspeccionar el servicio `odoo` sin tocar el resto del stack. **No es donde instalás o actualizás módulos** — eso vive en [gestionar-modulo](../modulos/gestionar-modulo.md), que para y levanta el servicio como parte de un `-i`/`-u` explícito, no de este runbook.

## Objetivo

El servicio de aplicación en el estado pedido.

## Comandos

```bash
make odoo-up
make odoo-down
make odoo-restart    # docker compose restart — no recrea el contenedor, no aplica un rebuild
make odoo-logs
make odoo-ps
make odoo-verify
```

`odoo-restart` no sirve para aplicar un cambio de imagen (un `docker compose build` nuevo) ni un cambio en `addons/` que necesite que Odoo relea el `addons_path` desde cero — para eso hace falta `odoo-down` + `odoo-up`.

**El primer arranque de una base vacía tarda más que un restart normal.** El entrypoint detecta que `ir_module_module` no existe y corre `-i base --stop-after-init` con la conexión explícita a `postgres:5432`, antes de arrancar el servidor — es el único caso en el que este comando dispara una instalación, y solo pasa una vez por base.

## Verificación

```bash
make odoo-verify
```

Cubre el servicio `healthy`, los logs sin errores de permisos, `smtp_server` cargado de verdad en el conf runtime (omitido en un stack con `ODOO_DISABLE_SMTP`), Odoo respondiendo en su `:8069`, los worktrees de `addons/` limpios, los módulos server-wide presentes en el árbol, la rama de addons coherente con la imagen, y los puertos sin publicar. Las tres rutas de Odoo en nginx y el certificado los cubre `nginx-verify`/`certbot-verify` — no este comando.

---

**Destructivo — sin target, a mano.** Tampoco sobrevivió un nuke acotado a este
servicio: el único que queda es `make nuke`, **global**, que se lleva `odoo-data`
junto con `pgdata` y todo lo demás. Para borrar solo el filestore:

```bash
docker compose rm -sf odoo
docker volume rm "${COMPOSE_PROJECT_NAME}_odoo-data"
```

Antes de correrlo en producción o staging, confirmá que hay un backup reciente y probado (ver [realizar-backup](../backup-restore/realizar-backup.md)); el filestore se recupera con [restore-perdida-total](../backup-restore/restore-perdida-total.md), no con este comando.
