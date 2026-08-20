# Restore de pérdida total del servidor

Se lee con producción caída, de apuro, probablemente de noche. Es autocontenido a propósito: no vas a tener ganas de saltar entre documentos.

El diseño de fondo está en [`docs/architecture.md`](../../architecture.md) § Estrategia de backup.

> **Si perdiste una de las dos passphrases de cifrado**, su repo es **irrecuperable**. No hay procedimiento. Este documento asume que las dos siguen custodiadas.

## Cuándo se usa

Servidor nuevo, disco vacío. Todo el estado tiene que venir de R2. Para un error lógico con el servidor intacto, ver [restore-pitr](restore-pitr.md); para el ejercicio sin incidente real, [restore-simulacro-semestral](restore-simulacro-semestral.md).

## Objetivo

El servidor reconstruido desde cero, con la base y el filestore al último punto disponible en R2, y el archivado funcionando de nuevo al terminar.

## A mano

**La trampa de este escenario:** si seguís [levantar-produccion](../entorno/levantar-produccion.md) de punta a punta, el entrypoint de Odoo inicializa una base nueva (`-i base`) en la fase Aplicación y te encontrás restaurando sobre un cluster que ya no está vacío. **El restore va antes de arrancar Odoo.**

**La regla de consistencia base ↔ filestore.** Un adjunto vive partido: la fila en `ir_attachment` (base) y el archivo en el filestore. La corrida de backup siempre hace pgBackRest primero y restic después, así que cada snapshot de restic es un superconjunto de lo que la base referenciaba en ese momento. En pérdida total no hay elección de timestamp: se restaura al final del WAL disponible y al último snapshot de restic, así que la regla se cumple sola.

## Comandos

**1. Seguir [levantar-produccion](../entorno/levantar-produccion.md) desde el principio hasta el `up -d postgres pgbouncer` de la fase Datos.** Un solo desvío, en la fase Cuentas externas: las dos passphrases de cifrado y las claves de R2 **salen de la copia custodiada, no se inventan** — esa fase asume un deploy virgen y hace generarlas. Passphrases nuevas dejan todo el repo ilegible.

**2. Saltear el `stanza-create` de la fase Datos.** La stanza ya existe en R2 — ese paso es solo para un deploy virgen, y correrlo acá falla por *system identifier* que no coincide. Solo confirmás que la ves:

```bash
docker compose stop -t 60 postgres
docker compose --profile restore up -d restore-db
docker compose exec restore-db pgbackrest info
```

**3. Restaurar** — sin `--type=time` restaura al final del WAL disponible, que es lo que querés ante pérdida total:

```bash
docker compose exec restore-db pgbackrest restore --delta
docker compose rm -sf restore-db
docker compose up -d postgres
docker compose logs -f postgres
```

**4. Restaurar el filestore** desde el último snapshot:

```bash
docker compose --profile restore up -d restore-files
docker compose exec restore-files restic restore latest --target /
docker compose rm -sf restore-files
```

El `--target /` es correcto: restic guarda rutas absolutas, el snapshot contiene `/data/odoo`, y en este contenedor `/data/odoo` **es** el volumen `odoo-data` montado rw.

**5. Recién ahora**, retomar [levantar-produccion](../entorno/levantar-produccion.md) en la verificación de la fase Datos (`make db-verify`) y seguir con la fase Aplicación. El entrypoint encuentra la base ya inicializada y no la toca.

**6. Completar las fases Protección y Observación, y el cierre.** En Protección, `restic init` va a decir `config file already exists` — es lo correcto, el repo ya está; **no lo fuerces**.

## Verificación

Las tres, no una. Cada una cubre una falla que las otras no ven:

1. **El dato volvió.** Consultar en Odoo un registro conocido y confirmar que está.
2. **Un adjunto se descarga de verdad.** Abrir un documento con adjunto en la interfaz de Odoo y **bajarlo**. No alcanza con que la fila exista en `ir_attachment`.
3. **El chequeo de integridad no reporta faltantes:**
   ```bash
   scripts/integrity-check.sh
   ```
   Salida esperada: `referenciados: N | faltantes: 0`, exit `0`.

### Después de un restore real

1. **Sacar un backup full inmediatamente** (`make backup-full`, ver [realizar-backup](realizar-backup.md)).
2. **Confirmar que el archivado volvió a andar:**
   ```bash
   docker compose exec -u postgres postgres pgbackrest check
   docker compose exec postgres sh -c 'ls /var/lib/postgresql/data/pg_wal/*.ready 2>/dev/null | wc -l'
   ```
   Esperado: `completed successfully` y `0`.
3. **Verificar que no quedaron contenedores de restore vivos:**
   ```bash
   docker compose ps --format '{{.Service}}'
   ```
4. **Anotar el RTO real** — cuánto tardó de punta a punta, desde servidor vacío hasta el sistema sirviendo.
