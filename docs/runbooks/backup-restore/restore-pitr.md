# Restore PITR (error lógico, disco intacto)

Se lee con producción caída o dañada, de apuro, probablemente de noche. Es autocontenido a propósito: no vas a tener ganas de saltar entre documentos.

El diseño de fondo (por qué R2, por qué dos herramientas, qué riesgo se aceptó) está en [`docs/architecture.md`](../../architecture.md) § Estrategia de backup.

> **Si perdiste una de las dos passphrases de cifrado** (`repo1-cipher-pass` de pgBackRest, o la de restic), su repo es **irrecuperable**. No hay procedimiento, no hay soporte, no hay recuperación técnica. Este documento asume que las dos siguen custodiadas.

## Cuándo se usa

El servidor está sano — alguien borró registros, una migración salió mal — y querés volver la base a un momento anterior al error. Es el caso dominante entre los tres escenarios de restore. Para pérdida total del servidor ver [restore-perdida-total](restore-perdida-total.md); para el ejercicio sin incidente real, [restore-simulacro-semestral](restore-simulacro-semestral.md).

## Objetivo

Base y filestore restaurados a un timestamp elegido, consistentes entre sí, con el archivado de WAL funcionando de nuevo al terminar.

## A mano

Tres datos, en este orden:

1. **¿A qué momento querés volver?** Timestamp concreto, con zona horaria. Los contenedores corren en UTC.
2. **¿Alguien sigue escribiendo?** Odoo tiene que estar detenido antes de tocar la base, o vas a restaurar sobre un blanco móvil.
3. **¿A qué commit de addons corresponde el snapshot que vas a usar?** Cada snapshot de restic lleva un registro de texto con el estado exacto que tenía `addons/` en el momento del backup:
   ```bash
   docker compose exec backup restic dump latest /data/meta/addons.txt
   ```
   Una fila por repo: categoría, nombre, rama, commit corto. Si el código actual del servidor no coincide con lo que corría cuando se tomó el backup (por ejemplo, promoviste un módulo después), volvé cada repo al commit que indica el registro: `git -C addons/<categoría>/<repo> checkout <commit>`. Es información, no una precondición: si el registro faltara, la base y el filestore restauran igual — se pierde solo la certeza de a qué código correspondían.

**La regla de consistencia base ↔ filestore.** Un adjunto vive partido: la fila en `ir_attachment` (base) y el archivo en el filestore. Restaurarlos desalineados es la falla silenciosa de este sistema — la base arranca sana y el problema aparece meses después. La corrida de backup siempre hace pgBackRest primero y restic después, así que cada snapshot de restic es un superconjunto de lo que la base referenciaba en ese momento:

> Elegí el **primer snapshot de restic tomado en o después** del momento al que restaurás la base.

Más nuevo que la base deja archivos huérfanos, inofensivos. Más viejo deja filas apuntando a archivos que no existen, destructivo. Si restaurás a un punto posterior al último snapshot, los adjuntos creados en el medio no están — no es un bug, es el RPO de ~24h del filestore. **No uses el filestore vivo como reemplazo de un snapshot**: el cron `_gc_file_store` de Odoo borra archivos que ninguna fila referencia.

## Comandos

**1. Frenar la escritura:**

```bash
docker compose stop odoo
docker compose stop -t 60 postgres
```

El `-t 60` no es opcional: con Odoo y PgBouncer conectados, Postgres no cierra en los 10s por defecto, Docker lo mata, y el `postmaster.pid` que queda bloquea el restore.

**2. Ver qué hay disponible** y elegir el punto:

```bash
docker compose --profile restore up -d restore-db
docker compose exec restore-db pgbackrest info
```

El rango `wal archive min/max` marca hasta dónde llega el PITR. Un target fuera de ese rango falla.

**3. Restaurar:**

```bash
docker compose exec restore-db pgbackrest restore \
  --delta \
  --type=time --target="2026-08-01 14:30:00+00" \
  --target-action=promote
```

- `--delta` compara y reescribe solo lo que difiere: mucho más rápido con el `pgdata` presente.
- `--target-action=promote` hace que Postgres salga de recovery solo al llegar al target. Sin eso queda en `pause` esperando un `pg_wal_replay_resume()` manual, lo que a las 3am se lee como "la base no arranca".
- El target lleva **zona horaria explícita** (`+00`). Sin ella, la interpretación depende del `TimeZone` del cluster.

**4. Bajar el contenedor de restore y arrancar la base:**

```bash
docker compose rm -sf restore-db
docker compose up -d postgres
docker compose logs -f postgres
```

Esperá `database system is ready to accept connections`. Hasta ahí, la base está reproduciendo WAL.

**5. Restaurar el filestore** al snapshot que corresponde según la regla de consistencia:

```bash
docker compose --profile restore up -d restore-files
docker compose exec restore-files restic snapshots
docker compose exec restore-files restic restore <snapshot-id> --target /
docker compose rm -sf restore-files
```

El `--target /` es correcto, no un error de tipeo: restic guarda rutas absolutas, el snapshot contiene `/data/odoo`, y en este contenedor `/data/odoo` **es** el volumen `odoo-data` montado rw.

**6. Levantar el resto:**

```bash
docker compose up -d
```

## Verificación

Las tres, no una. Cada una cubre una falla que las otras no ven:

1. **El dato volvió.** Consultar en Odoo el registro concreto que motivó el restore, y confirmar que está en el estado esperado para el timestamp elegido.
2. **Un adjunto se descarga de verdad.** Abrir un documento con adjunto en la interfaz de Odoo y **bajarlo**. No alcanza con que la fila exista en `ir_attachment`.
3. **El chequeo de integridad no reporta faltantes:**
   ```bash
   scripts/integrity-check.sh
   ```
   Salida esperada: `referenciados: N | faltantes: 0`, exit `0`. Cada línea `FALTA:` es un adjunto roto — si aparecen, el snapshot de restic elegido es **anterior** al punto de la base.

### Después de un restore real

1. **Sacar un backup full inmediatamente** (`make backup-full`, ver [realizar-backup](realizar-backup.md)): una promoción tras PITR abre una timeline nueva en Postgres, y el punto de partida limpio para todo lo que viene es una full sobre la timeline actual.
2. **Confirmar que el archivado volvió a andar:**
   ```bash
   docker compose exec -u postgres postgres pgbackrest check
   docker compose exec postgres sh -c 'ls /var/lib/postgresql/data/pg_wal/*.ready 2>/dev/null | wc -l'
   ```
   Esperado: `completed successfully` y `0`. Si el contador de `.ready` crece, el archivado quedó roto.
3. **Verificar que no quedaron contenedores de restore vivos:**
   ```bash
   docker compose ps --format '{{.Service}}'
   ```
   No deben aparecer `restore-db` ni `restore-files`.
4. **Anotar el RTO real** — cuánto tardó de punta a punta.
