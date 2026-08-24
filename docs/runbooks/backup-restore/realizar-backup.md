# Realizar backup

## Cuándo se usa

Operación normal, en producción: los timers de systemd ya corren esto solos (diario y mensual). Este runbook es para correrlo a mano — probar la cadena entera después de un cambio de config, o disparar una corrida fuera de horario.

No aplica a staging ni a development: la capa de backups es exclusiva de producción (ver `require-backups` en el Makefile) — escribir ahí pisaría la misma stanza de pgBackRest, el mismo repositorio de restic y las mismas métricas de la producción real.

## Objetivo

Un backup completo de las dos mitades del sistema —base vía pgBackRest, filestore vía restic— con el registro de qué commit de `addons/` corresponde a ese momento, y sin dejar el disco llenándose si algo del archivado falló silenciosamente.

## A mano

Ninguno para la corrida diaria. Para la mensual (`backup-full`), ninguno tampoco — la diferencia es solo qué tipo de backup de pgBackRest dispara.

## Comandos

```bash
make backup         # diaria: pgbackrest check → backup --type=diff → restic backup → forget --prune
make backup-full     # mensual: pgbackrest backup --type=full
make backup-check    # solo integridad: pgbackrest check + restic check, no escribe nada
```

**El orden dentro de `make backup` no es casual:** `pgbackrest check` corre primero porque los backups full/diff pueden seguir aparentando éxito mientras el archivado está roto — es la única forma de detectarlo antes de confiar en el resultado. pgBackRest va antes que restic, siempre: un snapshot de filestore más nuevo que el backup de base deja archivos huérfanos (inofensivo); uno más viejo deja filas de `ir_attachment` apuntando a archivos que no existen (destructivo y silencioso).

**Puede parecer trabada y no lo está.** pgBackRest no imprime nada hasta terminar — sube el cluster archivo por archivo, un objeto a R2 por cada uno. En una instalación con pocos datos ya son minutos, porque manda la latencia por objeto, no el tamaño total. **No le des Ctrl-C**: un full abortado deja basura parcial en el repositorio. Para ver que avanza, desde otra sesión:

```bash
docker compose exec -T postgres tail -f /var/log/pgbackrest/*-backup.log
```

La corrida deja además `state/meta/addons.txt` dentro del snapshot de restic — repo, rama y commit de cada worktree de producción en ese momento. Es lo único que le dice a un restore a qué código correspondían esos datos (ver [restore-pitr](restore-pitr.md) § "A qué commit de addons corresponde").

## Verificación

```bash
make backups-verify
```

Cubre el snapshot de restic, el full de pgBackRest, el registro de addons, los dos timers de systemd activos con el nombre de este stack, el `OnFailure=` cableado con su unit plantilla instalada, y que ningún contenedor del perfil `restore` esté corriendo.

Si el contenedor `backup` sale `health: starting` **no es un fallo**: con `interval: 1h` el primer chequeo que cuenta cae recién a la hora, y durante el `start_period` de 5 minutos los fallos no cuentan. **No lo recrees para forzarlo** — le cambiarías el hostname del contenedor, y con eso el grupo `(host, paths)` por el que restic agrupa la retención (`RESTIC_KEEP_*`).

Probar el aviso de fallo de punta a punta, sin esperar a que uno ocurra de verdad:

```bash
sudo make notify-test
```

Tiene que dar `Result=success` **y llegar el mail** a `ALERT_EMAIL_TO`. Dispara la unit real, no el script suelto: prueba el cableado, la ruta absoluta del `ExecStart` y el envío con la credencial que quedó en `secrets/`.

---

**Un backup sin probar no es un backup** — `PRINCIPLES.md` lo exige. La prueba real es el simulacro semestral: ver [restore-simulacro-semestral](restore-simulacro-semestral.md).
