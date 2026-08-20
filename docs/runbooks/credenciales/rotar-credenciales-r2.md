# Rotar credenciales de R2

## Cuándo se usa

El token de acceso al bucket de R2 venció, se filtró, o toca rotarlo por política. Es la credencial más sensible del stack: abre los dos repositorios de backup (pgBackRest y restic).

**Es una sola clave escrita en dos archivos, no dos credenciales.** `secrets/pgbackrest_r2_credentials` y `secrets/restic_r2_credentials` llevan el mismo par de acceso, en sintaxis INI distinta por herramienta — al rotarla hay que tocar los dos, o uno de los dos servicios queda con la clave vieja mientras el otro ya tiene la nueva.

## Objetivo

Los dos archivos actualizados, los dos consumidores (`postgres`, `backup`) recreados con el valor nuevo, la clave vieja revocada en R2 solo después de confirmar que la nueva funciona.

## A mano

Crear el token nuevo en Cloudflare R2: `Object Read & Write`, acotado al mismo bucket. **No lo revoques todavía** — si el reemplazo falla a mitad de camino, necesitás poder volver atrás.

## Comandos

```bash
echo "# 1 → Los dos archivos, mismo par de acceso, sintaxis propia de cada uno"
sudo -e secrets/pgbackrest_r2_credentials
sudo -e secrets/restic_r2_credentials
sudo make secrets-perms
```

**Recrear los dos consumidores, no reiniciarlos** — los secrets son bind-mounts de archivo atados al inode; un `restart` sobre un contenedor cuyo secret se reemplazó (no se editó in-place) sigue viendo el valor viejo, o directamente `No such file`.

```bash
echo "# 2 → pgBackRest vive dentro de postgres"
docker compose up -d --force-recreate postgres

echo "# 3 → restic vive en su propio contenedor"
docker compose up -d --force-recreate backup
```

## Verificación

```bash
make backup-check
```

Corre `pgbackrest check` + `restic check` sobre los dos repositorios, sin escribir nada. Los dos tienen que dar sano con la clave nueva.

Si alguno falla, la clave vieja todavía está activa en R2 — revertí el archivo correspondiente y volvé a recrear ese contenedor antes de seguir insistiendo con la nueva.

Recién con `backup-check` en verde, **revocar la clave vieja** en Cloudflare R2. Confirmar con una corrida real antes de dar el cambio por cerrado:

```bash
make backup
```
