# Rotar credenciales de R2

## Cuándo se usa

El token de acceso al bucket de R2 venció, se filtró, o toca rotarlo por política. Es la credencial más sensible del stack: abre el repositorio de backups.

**Un solo archivo.** `secrets/restic_r2_credentials` lleva el par de acceso en el
formato de AWS, que es lo que restic parsea.

## Objetivo

El archivo actualizado, `backup` —su único consumidor— recreado con el valor nuevo, la clave vieja revocada en R2 solo después de confirmar que la nueva funciona.

## A mano

Crear el token nuevo en Cloudflare R2: `Object Read & Write`, acotado al mismo bucket. **No lo revoques todavía** — si el reemplazo falla a mitad de camino, necesitás poder volver atrás.

## Comandos

```bash
sudo -e secrets/restic_r2_credentials
sudo make secrets-perms
```

**Recrear `backup`, no reiniciarlo** — los secrets son bind-mounts de archivo atados al inode; un `restart` sobre un contenedor cuyo secret se reemplazó (no se editó in-place) sigue viendo el valor viejo, o directamente `No such file`.

```bash
docker compose up -d --force-recreate backup
```

## Verificación

```bash
make backup-integrity
```

Corre `restic check` sobre el repositorio, sin escribir nada. Tiene que dar sano con la clave nueva.

Si falla, la clave vieja todavía está activa en R2 — revertí el archivo y volvé a recrear `backup` antes de seguir insistiendo con la nueva.

Recién con `backup-check` en verde, **revocar la clave vieja** en Cloudflare R2. Confirmar con una corrida real antes de dar el cambio por cerrado:

```bash
make backup-run
```
