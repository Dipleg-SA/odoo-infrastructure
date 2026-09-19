# Realizar backup

## Cuándo se usa

Antes de un cambio riesgoso —upgrade mayor, módulo nuevo, cambio de config de la base—
y para verificar a mano que la corrida automática funciona.

No aplica a prueba ni a development: **respaldar es exclusivo de producción**. El
entrypoint de prueba le pone `profiles: [restore]` al stack `backup`, así que
`require-backups` rechaza el target ahí, y su credencial de R2 es de solo lectura.

## Objetivo

Un backup completo de las dos mitades del estado —el dump de la base y el filestore—
**en el mismo snapshot de restic**, con la selección de commits que el contenedor Odoo
cargó al arrancar.

Que las dos mitades vayan juntas no es una comodidad: la base referencia archivos que
solo existen en el filestore, y respaldarlos por separado convierte la consistencia en
un procedimiento que hay que recordar en vez de una propiedad del backup.

## Flujo rápido

1. Verificar Odoo y ejecutar `backup-run` en producción.
2. Ejecutar `backup-integrity` si se necesita revisar el repositorio sin escribir.
3. Confirmar el snapshot completo con `backup-verify`.

## A mano

Odoo debe estar operativo y exponer `/tmp/odoo-addons-startup.json`. El backup falla
antes de restic si no puede asociar una selección ejecutada válida; no la reemplaza con
el candidato actual.

## Comandos

```bash
ENTORNO=produccion make backup-run        # dump + filestore en un snapshot, y forget --prune
ENTORNO=produccion make backup-integrity  # solo verifica el repositorio, no escribe nada
```

**El dump va sin comprimir, y no es un descuido.** Comprimido, zlib cambia el flujo de
bytes globalmente ante cualquier modificación y la deduplicación de restic cae a cero:
subiría el archivo entero todas las noches. Si alguien "optimiza" eso, el repositorio
crece sin control.

**La retención GFS la hace `forget` en la misma corrida** — 7 diarios, 4 semanales, 3
mensuales. En restic todo snapshot es completo, así que no hay una corrida distinta por
cadencia: no existe un `backup-full`.

**Puede tardar.** `pg_dump` relee la base entera en cada corrida. Si eso empieza a
irse de mano, `backup-run` avisa —no falla— al cruzar el umbral: es la señal de que la
base creció lo suficiente como para reconsiderar la estrategia de snapshot.

## Verificación

```bash
ENTORNO=produccion make backup-verify
```

Cubre el servicio `healthy`, que `r2.env` no tenga el placeholder sin reemplazar, que
el endpoint termine en `.r2.cloudflarestorage.com`, que el repositorio sea alcanzable
y tenga snapshots de **este** stack, que el último traiga **las dos mitades**
(`/data/dump` y `/data/odoo` — un snapshot con el filestore y sin la base restaura una
base que no existe), `addons-startup.json` dentro del snapshot y los dos timers activos
con el nombre de este checkout. Metadata anterior a la versión 2 es diagnóstico
histórico, no una selección aplicable.
