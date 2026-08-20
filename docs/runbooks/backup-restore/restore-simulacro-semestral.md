# Simulacro semestral de restore

## Cuándo se usa

[`PRINCIPLES.md`](../../../PRINCIPLES.md) lo exige (un backup sin probar no es un backup) y es lo único que confirma que la cadena entera sirve, sin esperar a un incidente real. **Contra un clon con otro nombre de proyecto, nunca contra producción.** Sembrar staging (ver [levantar-staging](../entorno/levantar-staging.md)) y hacer este simulacro son, en la práctica, la misma operación.

## Objetivo

Un clon efímero, restaurado desde R2, con el RTO medido y anotado, destruido al terminar sin dejar rastro.

## Comandos

```bash
docker compose -p simulacro --profile restore up -d restore-db
docker compose -p simulacro exec restore-db pgbackrest restore \
  --delta --archive-mode=off \
  --type=time --target="<T objetivo>" --target-action=promote
```

`--archive-mode=off` **no es opcional**: sin él, el clon hereda el `archive_command` del backup y empieza a empujar WAL a la stanza de producción, contaminando el repositorio desde el propio ejercicio que debía validarlo.

Al terminar, destruir el clon **con su volumen**:

```bash
docker compose -p simulacro --profile restore down -v
```

## Verificación

Las mismas tres de un restore real:

1. **El dato volvió** — consultar en Odoo un registro conocido para el timestamp elegido.
2. **Un adjunto se descarga de verdad** — no alcanza con que la fila exista en `ir_attachment`.
3. **El chequeo de integridad no reporta faltantes:**
   ```bash
   scripts/integrity-check.sh
   ```

Y **anotar el RTO medido** de esta corrida, para tener una serie comparable — no hay un objetivo previo fijado, la primera corrida establece la línea base.

---

**Dos límites conocidos antes del primer simulacro:**

- **El clon compite por memoria con producción.** Levantar el segundo stack con los mismos `mem_limit` duplica el presupuesto de las dos capas pesadas. Antes del ejercicio hay que decidir una de tres: correr el clon con `ODOO_MEM_LIMIT` y `POSTGRES_MEM_LIMIT` reducidos, detener producción mientras dura, o verificar sin levantar Odoo.
- **`scripts/integrity-check.sh` apunta al proyecto por defecto.** Invoca `docker compose exec` sin `-p`, así que durante un simulacro verifica **producción** y no el clon, y devuelve un OK falso. Se corrige anteponiendo `COMPOSE_PROJECT_NAME=<clon>`. Necesita `postgres` y `odoo` levantados: el perfil `restore` solo trae dos contenedores que duermen, ninguno sirve un `psql`. Qué servicios levanta el clon es la misma decisión del punto anterior.
