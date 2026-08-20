# Un secret rotado no surte efecto, o el contenedor reporta No such file

## Síntoma

Editaste un archivo bajo `secrets/` y el contenedor sigue usando el valor viejo, o directamente dice `No such file`.

## Diagnóstico

Los secrets son bind-mounts de **archivo**, atados al inode. Editarlos con algo que reemplace el archivo (`sed -i`, varios editores) desvincula el inode montado. El contenedor queda viendo el archivo viejo o ninguno, y **restaurar el contenido no lo arregla**.

## Fix

```bash
docker compose up -d --force-recreate <servicio>
```

Verificar además el GID con `make secrets-check`: si la herramienta recreó el archivo, probablemente también perdió el grupo. Es el mismo paso que ya incluyen los runbooks de [credenciales/](../../credenciales/).
