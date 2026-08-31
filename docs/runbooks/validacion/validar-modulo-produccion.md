# Validar módulo en producción

## Cuándo se usa

Justo después de aplicar un cambio en producción —el último paso de [gestionar-modulo § Actualizar](../modulos/gestionar-modulo.md#actualizar), incluida la primera vez que un módulo se instala ahí— para confirmar que quedó bien antes de dar el deploy por cerrado y seguir con otra cosa.

## Objetivo

El módulo funcionando en producción real, sin errores en los logs, y el estado general del stack sin regresiones — a diferencia de staging, acá cualquier problema es visible para usuarios reales, así que esta validación es rápida y de confirmación, no de exploración: lo exploratorio ya pasó en [validar-modulo-staging](validar-modulo-staging.md).

## Comandos

```bash
make odoo-modules
```

Confirma la versión instalada, leída de `ir_module_module` — la fuente de verdad, no una lista paralela.

```bash
docker compose logs --since 10m odoo | grep -iE 'error|traceback|warn'
```

## Verificación

```bash
make verify
```

Las seis capas en verde, nueve servicios corriendo —diez si tu `.env` tiene LAN activo—, ninguno del perfil `restore`. `certbot` no cuenta: corre con `--rm` y nunca queda arriba.

A mano:

- Probar el flujo específico del cambio en la UI de producción — con cuidado, porque acá los datos son reales: preferí un registro de prueba dedicado antes que uno que un usuario real esté mirando.
- Si el cambio tocó algo que dispara correo, confirmar que salió de verdad (acá SMTP sí está activo, a diferencia de staging).
- Si algo sale mal acá y no salió en staging, es una señal de que la validación de staging no cubrió el caso — vale la pena volver y ampliarla para la próxima, no solo arreglar el síntoma en producción.

---

Si algo requiere revertir, no hay un "deshacer" de módulo: el camino es un nuevo cambio a través de [gestionar-modulo § Actualizar](../modulos/gestionar-modulo.md#actualizar), validado de nuevo en staging. Si el problema es de datos, no de código, ver [backup-restore/](../backup-restore/).
