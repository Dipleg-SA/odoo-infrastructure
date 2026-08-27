# unable to verify certificate presented by ...r2.cloudflarestorage.com

## Síntoma

`restic` falla al conectar a R2 con un error de verificación de certificado.

## Diagnóstico

Falta el almacén de CAs raíz en la imagen que corre. La imagen oficial de restic lo
trae, así que el error significa que la imagen en uso no es la que el stack construye —
o que el reloj del host está lo bastante corrido como para que el certificado quede
fuera de su ventana de validez.

## Fix

Reconstruir la imagen del stack:

```bash
docker compose build backup && docker compose up -d backup
```

Si persiste, revisar la hora del host: un desfase de días invalida cualquier certificado.

```bash
timedatectl status
```

## Verificación

```bash
make backup-integrity
```

Lee datos reales del repositorio, así que si conecta y verifica, el problema se cerró.
