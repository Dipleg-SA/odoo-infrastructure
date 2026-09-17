# Rotar token de git remoto

## Cuándo se usa

El token de solo lectura de staging o producción (el que usa `repo-sync` para clonar/traer los repos privados del manifiesto) venció o toca rotarlo. La credencial de desarrollo se rota por su procedimiento propio. **No es un secret de Compose** — vive en `~/.git-credentials` del host, nunca dentro de un contenedor, porque el clonado ocurre en el host y ningún contenedor lo consume.

El archivo es **por máquina, no por checkout**: rotarlo una vez en el servidor cubre a producción y staging juntas —comparten `~/.git-credentials`, ver [crear-token-git-lectura](crear-token-git-lectura.md)—. Desarrollo usa una credencial distinta para gestión de ramas.

## Objetivo

`~/.git-credentials` actualizado en cada lugar donde vive, `repo-sync` funcionando de nuevo, el token viejo revocado.

## Flujo rápido

Actualizá todas las máquinas que usan el archivo antes de revocar el token anterior.

1. **Generar un token nuevo** con lectura de contenidos y ubicar cada máquina que lo usa; ver
   [A mano](#a-mano).
2. **Reemplazar la credencial en cada máquina** que ejecute staging o producción; ver
   [Comandos](#comandos).
3. **Probar `repo-sync` en todos los checkouts** y revocar el token anterior cuando todos pasen;
   ver [Verificación](#verificación).

## A mano

Generar el token nuevo en tu proveedor git — alcanza con lectura de contenidos sobre la organización donde viven los repos de addons. Anotar el vencimiento si es de los que expiran.

## Comandos

En cada máquina que ejecute staging o producción:

```bash
echo "# 1 → Sacar la línea vieja"
GIT_USER='tu-usuario'; GIT_HOST='github.com'
grep -v "https://$GIT_USER:.*@$GIT_HOST" ~/.git-credentials > ~/.git-credentials.tmp \
  && mv ~/.git-credentials.tmp ~/.git-credentials
```

```bash
echo "# 2 → Guardar la nueva (pegala y Enter, no se muestra)"
read -rs GIT_TOKEN && printf 'https://%s:%s@%s\n' "$GIT_USER" "$GIT_TOKEN" "$GIT_HOST" >> ~/.git-credentials \
  && chmod 600 ~/.git-credentials && echo "OK: credencial guardada"
```

No hace falta recrear ningún contenedor: `repo-sync` corre en el host, y usa `~/.git-credentials` en cada invocación.

## Verificación

```bash
make repo-sync
```

Sale con `0`, sin `Repository not found` ni `Authentication failed`. Si alguno de esos dos aparece, revisar que el token tenga los permisos justos (lectura de contenidos sobre la organización) antes de asumir que es un problema de otra cosa.

Recién con `repo-sync` limpio **en todos los checkouts que lo usaban**, revocar el token viejo en el proveedor git.
