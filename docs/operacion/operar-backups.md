# Operar backups

## Cuándo se usa

Para inspeccionar el contenedor de backup o ejecutar un backup y su verificación.

## Objetivo

Conservar base, filestore, addons y metadata de procedencia en el mismo snapshot de
producción para poder reconstruir el runtime.

## Flujo rápido

1. Levantar la capa de backup si está detenida.
2. Ejecutar la operación requerida y revisar sus logs.
3. Confirmar el snapshot con `backup-verify`.

## Comandos

```bash
ENTORNO=produccion make backup-up
ENTORNO=produccion make backup-run
ENTORNO=produccion make backup-integrity
ENTORNO=produccion make backup-verify
ENTORNO=produccion make backup-logs
```

El backup registra el `ODOO_IMAGE` usado como dato diagnóstico junto con la procedencia
de `runtime/addons/catalogo.txt`, base y filestore. La imagen no se restaura como estado:
si hace falta, se reconstruye explícitamente a partir de los candidatos y la edición.

Para restaurar en staging:

```bash
ENTORNO=staging make restore SNAPSHOT=latest
```

Para una restauración productiva, detené Odoo, conservá el snapshot asociado y ejecutá
el procedimiento de restore aprobado. Después construí, levantá y verificá la imagen
seleccionada.

## Verificación

`ENTORNO=produccion make backup-verify` debe confirmar snapshots, base, filestore,
registro de addons y metadata de procedencia. Staging solo lee el repositorio y no
ejecuta `backup-run`.
