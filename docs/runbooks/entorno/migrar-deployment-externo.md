# Migrar un deployment externo a este stack

Traer la base y el filestore de un Odoo que no pertenece a este stack —otro servidor, otro compose, otra herramienta— a un entorno levantado con este repositorio.

**No es un restore.** Todo lo que hay en [`backup-restore/`](../backup-restore/) recupera desde el repositorio de backups *de esta familia de stacks*. Un deployment ajeno no está ahí: el puente es un dump lógico, y el procedimiento es otro.

## Cuándo se usa

Una sola vez por deployment, al adoptar este stack sobre datos que ya existen. Por eso no hay target de `make`: un comando que se corre una vez y nunca más no gana nada envuelto.

Para levantar un entorno vacío, ver [levantar-produccion](levantar-produccion.md). Para recuperar *este* stack de un incidente, [restore-pitr](../backup-restore/restore-pitr.md) o [restore-perdida-total](../backup-restore/restore-perdida-total.md).

## Objetivo

La base y el filestore del deployment de origen sirviendo desde este stack, bajo el nombre de base que el stack exige, con los módulos al día y el backup propio corriendo al terminar.

## A mano

Cuatro cosas antes de tocar nada. La primera es eliminatoria.

**1. El mayor de Odoo tiene que coincidir.** Un dump lógico copia el esquema tal cual: no migra entre versiones mayores.

```bash
docker exec <contenedor-odoo-origen> odoo --version
grep '^FROM odoo:' stacks/odoo/image/Dockerfile
```

Si los mayores difieren, **este runbook no aplica**: es un upgrade de versión mayor, y la vía en la edición comunitaria está en [`docs/architecture.md`](../../architecture.md) § Upgrade de versión mayor. Si coinciden en el mayor pero no en el build, seguí — el paso 6 lo resuelve.

**2. Los módulos instalados en origen tienen que existir en este checkout.** Es el trabajo real de la migración; el dump es la parte fácil.

```bash
docker exec -u postgres <contenedor-db-origen> psql -d <base-origen> -tAc \
  "SELECT name FROM ir_module_module WHERE state = 'installed' ORDER BY name"
```

Cada nombre técnico de esa lista que no sea de la base de Odoo tiene que estar en `addons/addons.txt` de este checkout, en la rama que fija `ADDONS_BRANCH`. Si falta uno, la base restaurada arranca con registros que apuntan a código que no está.

**3. El nombre de base es fijo.** Este stack no lo parametriza: el entrypoint corre `-d odoo`, y `stacks/odoo/config/odoo.conf` trae `dbfilter = ^odoo$` con `list_db = False`. La base de origen aterriza llamándose `odoo` se llamara como se llamara, y el directorio del filestore se renombra con ella — el filestore se indexa por nombre de base.

**4. La regla de consistencia base ↔ filestore.** Un adjunto vive partido: la fila en `ir_attachment` y el archivo en el filestore. Copiarlos desalineados es la falla silenciosa de este sistema — arranca sano y el problema aparece meses después.

> **Frená el Odoo de origen antes del dump y dejalo frenado hasta terminar la copia del filestore.**

Con el origen detenido no hay deriva posible entre las dos mitades. Si no podés detenerlo, el orden es base primero y filestore después, igual que la corrida de backup: así el filestore queda como superconjunto de lo que la base referencia, que deja archivos huérfanos —inofensivos— en vez de filas rotas.

**Ensayalo contra staging antes que contra producción.** Tiene la capa de restore y el correo saliente cortado por diseño, así que el ensayo no manda mail real. `development` no tiene capa de restore: el paso 5 no corre ahí.

## Comandos

**1. Detener el origen y sacar el dump:**

```bash
docker stop <contenedor-odoo-origen>
docker exec -u postgres <contenedor-db-origen> pg_dump -Fc -d <base-origen> > /tmp/origen.dump
```

`-Fc` (custom) y no SQL plano: lo restaura `pg_restore`, que es el que tiene que ser el **nuevo**. Un dump de un Postgres viejo entra en uno nuevo; al revés no.

**2. Dejar la base destino vacía.** Postgres se queda **arriba** — lo que baja es todo lo que le escribe:

```bash
docker compose stop odoo
docker compose exec -T -u postgres postgres psql -U odoo -d postgres -v ON_ERROR_STOP=1 \
  -c 'DROP DATABASE IF EXISTS odoo;' \
  -c 'CREATE DATABASE odoo OWNER odoo;'
```

Odoo tiene que estar detenido: `DROP DATABASE` falla mientras quede una conexión abierta.

**3. Restaurar la base:**

```bash
docker compose exec -T -u postgres postgres pg_restore -U odoo -d odoo --no-owner --role=odoo < /tmp/origen.dump
```

`--no-owner --role=odoo` deja todo perteneciendo al rol de este stack, cualquiera fuera el dueño en origen. Un dump lógico no trae roles, así que el rol `odoo` de acá conserva su propia contraseña del secret.

**4. Sacar el filestore del origen:**

```bash
docker cp <contenedor-odoo-origen>:<data_dir-origen>/filestore/<base-origen> /tmp/filestore-origen
docker stop <contenedor-odoo-origen>   # si lo habías vuelto a levantar
```

**5. Meterlo en el volumen, con el nombre y el owner correctos.** Se hace con el stack `backup`, que ya monta `odoo-data` con escritura; se eleva a root en la invocación, como en cualquier restore.

```bash
docker compose up -d backup
docker compose exec -u 0:0 backup mkdir -p /data/odoo/filestore
docker cp /tmp/filestore-origen <proyecto>-backup:/data/odoo/filestore/odoo
docker compose exec -u 0:0 backup chown -R 100:101 /data/odoo/filestore
```

El `docker cp` hace el renombrado en el mismo movimiento: el directorio de origen llega como `odoo`, que es el nombre que el stack espera. `<proyecto>` es el `COMPOSE_PROJECT_NAME` del `.env`.

**6. Neutralizar — solo si el destino no es producción.** Sin esto la copia manda mail y pega contra las integraciones reales del origen:

```bash
docker compose run --rm odoo -d odoo --stop-after-init neutralize
```

**7. Levantar y poner los módulos al día:**

```bash
docker compose up -d
make odoo-update MODULES=all
```

El `-u all` no es opcional aunque el mayor coincida: entre builds de una misma serie hay versiones de módulo que suben, y sin la actualización el esquema queda a medio camino.

## Verificación

Las cuatro. Cada una cubre una falla que las otras no ven.

1. **El dato está.** Consultar en Odoo un registro conocido del origen y confirmar que aparece.
2. **Un adjunto se descarga de verdad.** Abrir un documento con adjunto en la interfaz y **bajarlo**. No alcanza con que la fila exista en `ir_attachment`.
3. **No quedaron módulos a medias:**
   ```bash
   docker compose exec -T -u postgres postgres psql -U odoo -d odoo -tAc \
     "SELECT name, state FROM ir_module_module WHERE state NOT IN ('installed','uninstalled')"
   ```
   Salida esperada: vacía. Cada fila es un módulo que la lista del punto 2 de *A mano* no cubrió.
4. **El chequeo de integridad no reporta faltantes:**
   ```bash
   scripts/integrity-check.sh
   ```
   Salida esperada: `referenciados: N | faltantes: 0`, exit `0`. Cada línea `FALTA:` es un adjunto cuya fila vino en el dump y cuyo archivo no vino en el filestore.

### Al terminar

1. **Backup full inmediato** (`make backup-integrity`, ver [realizar-backup](../backup-restore/realizar-backup.md)): el primer punto de partida limpio del stack nuevo es sobre los datos migrados, no sobre la base vacía que había antes.
2. **Confirmar que el archivado corre:**
   ```bash
   make backup-integrity
   ```
   Esperado: `completed successfully`.
3. **Borrar el dump y la copia del filestore del host** — `/tmp/origen.dump` y `/tmp/filestore-origen` son una copia completa de la base de producción sin cifrar.
4. **No apagar el deployment de origen todavía.** Es el único rollback que hay hasta que la verificación cierre, y sirve de archivo de consulta.
