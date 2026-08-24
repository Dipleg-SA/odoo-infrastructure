# Crear el token de git de solo lectura

## Cuándo se usa

Antes de sincronizar addons — lo pide `addons-sync` para clonar los repos privados del manifiesto (los públicos no lo necesitan). **No es un secret de Compose**: vive en `~/.git-credentials` del host, nunca dentro de un contenedor, porque el clonado ocurre en el host y ningún contenedor lo consume.

Se genera **una vez por máquina**, no por checkout: `credential.helper store` se configura `--global` y escribe en `~/.git-credentials`, así que producción y staging en el mismo servidor comparten uno solo. Hace falta uno nuevo en cada máquina de desarrollo (ver [levantar-desarrollo](levantar-desarrollo.md)) y en cada stack que viva en otro host.

## Objetivo

Un token de solo lectura sobre la organización donde viven los repos de addons, guardado en el credential store de git de este checkout.

## A mano

Generar el token en tu proveedor git (GitHub, GitLab…) — alcanza con lectura de contenidos sobre la organización. Anotá el vencimiento si es de los que expiran.

## Comandos

```bash
echo "# 1 → Completá tu usuario y el host HTTPS de los repos de addons — no un alias SSH propio"
GIT_USER='tu-usuario'; GIT_HOST='github.com'
echo "usuario: $GIT_USER"; echo "host: $GIT_HOST"
```

```bash
echo "# 2 → Token en el credential store del host (pegalo y Enter, no se muestra)"
git config --global credential.helper store
read -rs GIT_TOKEN && printf 'https://%s:%s@%s\n' "$GIT_USER" "$GIT_TOKEN" "$GIT_HOST" >> ~/.git-credentials \
  && chmod 600 ~/.git-credentials && echo "OK: credencial guardada"
```

## Verificación

Todavía no hay manifiesto de addons que sincronizar en un checkout nuevo — la prueba real es `make addons-sync` una vez clonado el repositorio (ver [levantar-produccion](levantar-produccion.md) o [levantar-desarrollo](levantar-desarrollo.md)). Por ahora, alcanza con confirmar que el archivo quedó bien armado:

```bash
grep "$GIT_HOST" ~/.git-credentials
```

Tiene que mostrar la línea con tu usuario — nunca el token en texto plano en ningún otro archivo ni en el historial de la shell (por eso el `read -rs`).

---

Para rotarlo más adelante, en cada checkout que lo usa: [rotar-token-git](../credenciales/rotar-token-git.md).
