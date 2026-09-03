# Contribuir

## Antes de tocar código

Leé [`PRINCIPLES.md`](PRINCIPLES.md) — son las reglas que este stack sigue siempre, con
el motivo de cada una — y [`ARCHITECTURE.md`](ARCHITECTURE.md) para el resto del
racional: por qué cada herramienta y no otra, qué se descartó y por qué. Un cambio que
contradice un principio **obligatorio** sin un motivo escrito nuevo no se acepta; uno
que reabre una decisión ya evaluada en `ARCHITECTURE.md` necesita evidencia nueva, no
solo preferencia.

## Idioma

Todo el repositorio está en español: código, comentarios, commits, documentación,
salida de los scripts. Los identificadores (servicios, variables, targets) quedan en
inglés donde ya lo están. El estilo de comentarios en archivos versionados de código y
config está en [`.claude/rules/comment-style.md`](.claude/rules/comment-style.md) y es
obligatorio.

## Qué es agnóstico y qué no

Este repo es el **producto**: genérico, sin rastros de ningún deployment concreto.
Cualquier valor que solo sirva a un deployment particular —hostnames, IPs, cantidades de
RAM, fechas, nombres de proveedores como ejemplo obligatorio— es un defecto en un PR, no
un detalle menor.

## Probar el cambio

Dos verificaciones distintas, no intercambiables:

- **`make test`** corre sin Docker levantado ni red, sobre lo que se puede afirmar
  leyendo el repositorio (contrato de los entrypoints, `addons.sh` contra repos git de
  verdad, los derivadores de scripts contra los stubs de `tests/stubs/`).
- **`make verify`** dice en qué estado está un deploy real, y necesita el sistema
  corriendo.

Al tocar un script, la pregunta que importa es si el test **falla** cuando se rompe lo
que dice cubrir — mutá el código y comprobalo. Al tocar un `compose.yaml`, la
verificación más fuerte es que la config resuelta no cambie:

```bash
docker compose config > /tmp/antes.yaml
# … cambio …
docker compose config | diff /tmp/antes.yaml -
```

## Proponer el cambio

Rama descriptiva desde `main`, PR contra `main`. El mensaje de commit y el título del PR
van en español, en imperativo, con el área que tocan adelante (`docs:`, `make:`,
`scripts/addons.sh:`, etc.) — mirá el historial reciente para el tono exacto. Un PR
grande que mezcla áreas sin relación se separa en varios: el diff acotado es lo que hace
auditable de un vistazo qué cambió y por qué.
