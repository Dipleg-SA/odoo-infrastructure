# Restore y recuperación ante desastre

Se lee con producción caída, de apuro, probablemente de noche. Por eso está separado de [`INSTALL.md`](../INSTALL.md): no querés estar navegando un runbook de instalación mientras la base no arranca.

El diseño de fondo (por qué R2, por qué dos herramientas, qué riesgo se aceptó) está en [`docs/architecture.md`](architecture.md) § Estrategia de backup. Acá está solo el procedimiento.

> **Si perdiste una de las dos passphrases de cifrado** (`repo1-cipher-pass` de pgBackRest, o la de restic), su repo es **irrecuperable**. No hay procedimiento, no hay soporte, no hay recuperación técnica. Este documento asume que las dos siguen custodiadas.

## Antes de tocar nada

Tres datos, en este orden:

1. **¿Qué se rompió?** Un error lógico con el disco intacto (alguien borró registros, una migración salió mal) es el **Escenario A**. Pérdida del servidor o del disco es el **Escenario B**. Si no se rompió nada y esto es el ejercicio semestral, es el **Escenario C**.
2. **¿A qué momento querés volver?** Timestamp concreto, con zona horaria. Los contenedores corren en UTC.
3. **¿Alguien sigue escribiendo?** Odoo tiene que estar detenido antes de tocar la base, o vas a restaurar sobre un blanco móvil.

**Una advertencia sobre `make restore-up`:** el servicio `restore-db` monta el volumen `pgdata` **de producción**. En el proyecto por defecto, un `pgbackrest restore` pisa la base real — que es exactamente lo que querés en los escenarios A y B, y exactamente lo que **no** querés en el C. El simulacro corre siempre bajo otro nombre de proyecto (`-p simulacro`).

## Qué vive dónde

| Qué | Herramienta | Dónde | Se restaura con |
|---|---|---|---|
| Base de datos (cluster completo) | pgBackRest | R2, prefijo `pgbackrest/` | servicio `restore-db` (misma imagen que `postgres`, uid 999) |
| Filestore (adjuntos) | restic | R2, prefijo `restic/` | servicio `restore-files` (uid 100:101, monta `odoo-data` rw) |

Dos cosas que sorprenden si no las sabés de antemano:

- **pgBackRest restaura el cluster entero**, no una base suelta. No existe "restaurar solo la tabla X" ni "solo la base `odoo`" — volvés todo el `pgdata` a un punto en el tiempo.
- **Los dos servicios de restore duermen** (`entrypoint: sleep infinity`). Levantarlos no restaura nada; son contenedores donde vos ejecutás los comandos a mano. Están fuera de `make up` por `profiles: [restore]`.

## La regla de consistencia base ↔ filestore

Un adjunto vive partido: la fila en `ir_attachment` (base) y el archivo en el filestore. **Restaurarlos desalineados es la falla silenciosa de este sistema** — la base arranca sana y el problema aparece meses después, cuando alguien abre un documento viejo.

La corrida de backup siempre hace pgBackRest primero y restic después, así que **cada snapshot de restic es un superconjunto de lo que la base referenciaba en ese momento**. De ahí sale la regla:

> Elegí el **primer snapshot de restic tomado en o después** del momento al que restaurás la base.

Más nuevo que la base deja archivos huérfanos, que son inofensivos. Más viejo deja filas apuntando a archivos que no existen, que es destructivo.

Si restaurás a un punto posterior al último snapshot (ej. PITR a las 14:00 de hoy, último snapshot a las 02:00), los adjuntos creados en el medio **no están**. Eso no es un bug, es el RPO de ~24h del filestore documentado en `architecture.md`. El chequeo de integridad los va a listar uno por uno.

**No uses el filestore vivo como reemplazo de un snapshot**, aunque el disco esté intacto y parezca más completo. El cron `_gc_file_store` de Odoo borra archivos que ninguna fila referencia, así que un estado pasado de la base puede referenciar archivos que el GC ya limpió.

## A qué commit de addons corresponde el snapshot

Desde el paso a bind-mount, `addons/` no está pineado en este repo — `git-aggregator` se fue, y lo que corre en producción es lo que `19.0` apunte hoy en cada repo. Cada snapshot de restic lleva, además del filestore, un registro de texto con el estado exacto que tenía `addons/production/` en el momento del backup:

```bash
docker compose exec backup restic dump latest /data/meta/addons.txt
```

Una fila por repo: categoría, nombre, rama, commit corto. Si el código actual del servidor no coincide con lo que corría cuando se tomó el backup que estás restaurando (por ejemplo, promoviste un módulo después), volvé cada repo al commit que indica el registro:

```bash
git -C addons/production/<categoría>/<repo> checkout <commit>
```

Esto es información, no una precondición del restore — si el registro faltara en un snapshot viejo (falló al generarse, o el snapshot es anterior a la capa correspondiente), la base y el filestore restauran igual. Lo que se pierde es solo la certeza de a qué código correspondían.

---

## Escenario A — PITR (error lógico, disco intacto)

El caso dominante. El servidor está sano; querés volver la base a un momento anterior al error.

1. **Frenar la escritura:**

   ```bash
   docker compose stop odoo
   docker compose stop -t 60 postgres
   ```

   El `-t 60` no es opcional: con Odoo y PgBouncer conectados, Postgres no cierra en los 10s por defecto, Docker lo mata, y el `postmaster.pid` que queda bloquea el restore (ver [`troubleshooting.md`](troubleshooting.md)).

2. **Ver qué hay disponible** y elegir el punto:

   ```bash
   docker compose --profile restore up -d restore-db
   docker compose exec restore-db pgbackrest info
   ```

   El rango `wal archive min/max` marca hasta dónde llega el PITR. Un target fuera de ese rango falla.

3. **Restaurar:**

   ```bash
   docker compose exec restore-db pgbackrest restore \
     --delta \
     --type=time --target="2026-08-01 14:30:00+00" \
     --target-action=promote
   ```

   - `--delta` compara y reescribe solo lo que difiere, en vez de vaciar y bajar todo: mucho más rápido con el `pgdata` presente.
   - `--target-action=promote` hace que Postgres **salga de recovery solo** al llegar al target. Sin eso queda en `pause` esperando un `pg_wal_replay_resume()` manual, lo que a las 3am se lee como "la base no arranca".
   - El target lleva **zona horaria explícita** (`+00`). Sin ella, la interpretación depende del `TimeZone` del cluster.

4. **Bajar el contenedor de restore y arrancar la base:**

   ```bash
   docker compose rm -sf restore-db
   docker compose up -d postgres
   docker compose logs -f postgres
   ```

   Esperá `database system is ready to accept connections`. Hasta ahí, la base está reproduciendo WAL.

5. **Restaurar el filestore** al snapshot que corresponde según la regla de consistencia:

   ```bash
   docker compose --profile restore up -d restore-files
   docker compose exec restore-files restic snapshots
   docker compose exec restore-files restic restore <snapshot-id> --target /
   docker compose rm -sf restore-files
   ```

   El `--target /` es correcto, no un error de tipeo: restic guarda rutas absolutas, el snapshot contiene `/data/odoo`, y en este contenedor `/data/odoo` **es** el volumen `odoo-data` montado rw.

6. **Levantar el resto y verificar** (ver "Verificación post-restore"):

   ```bash
   docker compose up -d
   ```

## Escenario B — Pérdida total del servidor

Servidor nuevo, disco vacío. Todo el estado tiene que venir de R2.

**La trampa de este escenario:** si seguís `INSTALL.md` de punta a punta, el entrypoint de Odoo inicializa una base nueva (`-i base`) en la fase **Aplicación** y te encontrás restaurando sobre un cluster que ya no está vacío. **El restore va antes de arrancar Odoo.**

1. **Seguir `INSTALL.md` desde el principio hasta el `up -d postgres pgbouncer` de la fase «Datos».** Un solo desvío, en la fase «Cuentas externas»: las dos passphrases de cifrado y las claves de R2 **salen de la copia custodiada, no se inventan** — ese documento asume un deploy virgen y te hace generarlas. Passphrases nuevas dejan todo el repo ilegible.

2. **Saltear el `stanza-create` de la fase «Datos».** La stanza ya existe en R2 — ese paso es solo para un deploy virgen, y correrlo acá falla por *system identifier* que no coincide. Solo confirmás que la ves:

   ```bash
   docker compose stop -t 60 postgres
   docker compose --profile restore up -d restore-db
   docker compose exec restore-db pgbackrest info
   ```

3. **Restaurar** — sin `--type=time` restaura al final del WAL disponible, que es lo que querés ante pérdida total:

   ```bash
   docker compose exec restore-db pgbackrest restore --delta
   docker compose rm -sf restore-db
   docker compose up -d postgres
   docker compose logs -f postgres
   ```

4. **Restaurar el filestore** desde el último snapshot (paso 5 del Escenario A, con `restic restore latest --target /`).

5. **Recién ahora**, retomar `INSTALL.md` en la verificación de la fase «Datos» (`make verify-db`) y seguir con la fase «Aplicación» (addons, build y `up -d odoo`). El entrypoint encuentra la base ya inicializada y no la toca.

6. Completar las fases «Protección» y «Observación», y el cierre. En Protección, `restic init` va a decir `config file already exists` — es lo correcto, el repo ya está; **no lo fuerces**.

## Escenario C — Simulacro semestral

[`PRINCIPLES.md`](../PRINCIPLES.md) lo exige (un backup sin probar no es un backup) y es lo único que confirma que la cadena entera sirve. **Contra un clon con otro nombre de proyecto, nunca contra producción.**

```bash
docker compose -p simulacro --profile restore up -d restore-db
docker compose -p simulacro exec restore-db pgbackrest restore \
  --delta --archive-mode=off \
  --type=time --target="<T objetivo>" --target-action=promote
```

`--archive-mode=off` **no es opcional**: sin él, el clon hereda el `archive_command` del backup y empieza a empujar WAL a la stanza de producción, contaminando el repo desde el propio ejercicio que debía validarlo.

Al terminar, destruir el clon **con su volumen**:

```bash
docker compose -p simulacro --profile restore down -v
```

Verificar las tres cosas de "Verificación post-restore", y **anotar el RTO medido** de cada corrida para tener una serie comparable — el spec no fija un objetivo previo, la primera corrida establece la línea base.

**Dos límites conocidos antes del primer simulacro:**

- **El clon compite por memoria con producción.** Levantar el segundo stack con los mismos `mem_limit` duplica el presupuesto de las dos capas pesadas. Antes del ejercicio hay que decidir una de tres: correr el clon con `ODOO_MEM_LIMIT` y `POSTGRES_MEM_LIMIT` reducidos, detener producción mientras dura, o verificar sin levantar Odoo.
- **`scripts/integrity-check.sh` no sirve tal cual para el simulacro.** Invoca `docker compose exec` sin `-p`, así que apunta al proyecto por defecto — es decir, a **producción**, no al clon: correrlo durante un simulacro verifica el stack equivocado y devuelve un OK falso. Esa mitad se arregla anteponiendo `COMPOSE_PROJECT_NAME=<clon>`. La otra no: el script necesita `postgres` y `backup` corriendo, y el perfil `restore` levanta dos contenedores que solo duermen, ninguno de los cuales sirve un `psql`. Qué servicios levanta el clon es la misma decisión del punto anterior.

---

## Verificación post-restore

Las tres, no una. Cada una cubre una falla que las otras no ven:

1. **El dato volvió.** Consultar en Odoo el registro concreto que motivó el restore, y confirmar que está en el estado esperado para el timestamp elegido.

2. **Un adjunto se descarga de verdad.** Abrir un documento con adjunto en la interfaz de Odoo y **bajarlo**. No alcanza con que la fila exista en `ir_attachment`: eso es justamente lo que se ve bien cuando el filestore quedó desalineado.

3. **El chequeo de integridad no reporta faltantes:**

   ```bash
   scripts/integrity-check.sh
   ```

   Recorre cada `store_fname` de `ir_attachment` y confirma que el archivo está en el filestore. Salida esperada: `referenciados: N | faltantes: 0`, con exit `0`. Cada línea `FALTA:` es un adjunto roto — si aparecen, el snapshot de restic elegido es **anterior** al punto de la base (releer "La regla de consistencia").

## Después de un restore real

Solo aplica a los escenarios A y B; el simulacro se destruye y no deja nada.

1. **Sacar un backup full inmediatamente:**

   ```bash
   make backup-full
   ```

   Una promoción tras PITR abre una **timeline nueva** en Postgres. Los backups previos siguen siendo válidos, pero el punto de partida limpio para todo lo que viene es una full sobre la timeline actual.

2. **Confirmar que el archivado volvió a andar:**

   ```bash
   docker compose exec -u postgres postgres pgbackrest check
   docker compose exec postgres sh -c 'ls /var/lib/postgresql/data/pg_wal/*.ready 2>/dev/null | wc -l'
   ```

   Esperado: `completed successfully` y `0`. Si el contador de `.ready` crece, el archivado quedó roto y el disco se va a llenar.

3. **Verificar que no quedaron contenedores de restore vivos:**

   ```bash
   docker compose ps --format '{{.Service}}'
   ```

   No deben aparecer `restore-db` ni `restore-files`. Si quedaron, `make restore-down`.

4. **Anotar el RTO real** — cuánto tardó de punta a punta. Es el mismo dato que produce el simulacro, y el de un incidente real vale más.
