# restic forget no borra lo que se espera

## Síntoma

`restic forget` deja snapshots que deberían haber caído según la política de retención.

## Diagnóstico

La política se aplica **por grupo `(host, paths)`**. Si una corrida respaldó un path distinto, forma su propio grupo y `keep-daily` lo conserva aunque sea viejo.

## Fix

Con el script estándar (`make backup`) no pasa, siempre el mismo path. Si aparece, alguien corrió un `restic backup` manual sobre otra ruta — revisar el historial de comandos antes de asumir que la retención está rota.
