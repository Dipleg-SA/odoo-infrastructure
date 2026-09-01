# Validar módulo en staging

## Cuándo se usa

**Obligatorio, sin excepción por confianza en el código.** `PRINCIPLES.md` exige probar en staging todo cambio riesgoso —upgrade mayor, módulo nuevo, cambio de config de la base— antes de aplicarlo a producción, incluso cuando el código ya vive en la rama de versión. Es el paso que [gestionar-modulo § Actualizar](../modulos/gestionar-modulo.md#actualizar) —también para la primera vez que un módulo se instala en un entorno— da por hecho entre "traer y validar" y "promover".

## Objetivo

El comportamiento confirmado contra datos reales —staging se siembra restaurando producción—, sin que nada de la prueba haya salido del entorno de staging.

## Comandos

```bash
make repo-sync
make addons-deps   # + build si el cambio agregó una dependencia Python
make addons-update MODULES=<nombre_tecnico>   # o addons-install, si es la primera vez de este módulo
```

Revisar los logs de la corrida:

```bash
docker compose logs --since 5m odoo | grep -iE 'error|traceback|warn'
```

## Verificación

```bash
make verify
```

En staging, las capas ausentes (backups, observabilidad, `dnsmasq`) salen como `--`, no en rojo — no es un fallo, es que ese entorno no las lleva.

A mano, específico de este módulo:

- Probar el flujo real en la UI de staging, con los datos reales que trajo el último restore — es la única de las tres validaciones que corre contra un volumen de datos comparable al de producción.
- **Confirmar que no salió correo real.** Staging no lleva credencial SMTP (`SMTP_HOST` vacío en su entrypoint) a propósito: un `-u` que dispare notificaciones, o una tarea programada que venía en la base restaurada, no debe mandar mail de verdad a clientes reales desde el entorno que existe para romper cosas. Si tu cambio depende de que el correo salga, revisar en cambio que Odoo lo haya encolado y fallado al enviar — eso es lo esperado acá, no un bug.
- Si el módulo toca datos existentes (no solo vistas o lógica nueva), revisar contra los datos reales de staging que la migración/`-u` no rompió nada que ya estaba — es la ventaja de validar acá y no solo en desarrollo con datos de demo.

---

Con esto en verde, seguí a la promoción y aplicación en producción — el resto de [gestionar-modulo § Actualizar](../modulos/gestionar-modulo.md#actualizar) — y después a [validar-modulo-produccion](validar-modulo-produccion.md).
