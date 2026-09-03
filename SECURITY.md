# Seguridad

## Alcance

Este archivo cubre vulnerabilidades en la infraestructura misma —los `compose.yaml`,
los `Dockerfile`, los scripts, el manejo de secretos, la exposición de red— no en Odoo,
en sus módulos, ni en las imágenes base de terceros que este repo consume. Un problema
en esas capas va a su propio proyecto.

Las decisiones de seguridad que ya se tomaron, y por qué, están en
[`PRINCIPLES.md`](PRINCIPLES.md) y en [`ARCHITECTURE.md`](ARCHITECTURE.md) —en
particular «Secretos», «Borde y red» y «Escaneo de vulnerabilidades»—. Vale la pena
revisarlas antes de reportar: parte de lo que puede parecer un hallazgo es una
decisión consciente y ya documentada, con su costo aceptado explícito.

## Versión soportada

Solo el último tag. No hay ramas de mantenimiento paralelas ni backport de parches a
versiones anteriores — actualizar es `git fetch --tags && git checkout <último tag>`.

## Cómo reportar

**No abras un issue público.** Usá el botón *Report a vulnerability* de la pestaña
Security de este repositorio en GitHub (GitHub Security Advisories) — llega en privado,
sin exponer el detalle mientras no hay parche.

Incluí, en lo posible: el stack afectado, los pasos para reproducir, y el impacto que
ves (qué se compromete y bajo qué condición de red o acceso).

## Qué esperar

Mantenido por una sola persona, sin SLA formal. Se confirma la recepción y se corrige lo
que corresponda; si el reporte señala un límite ya conocido y aceptado (por ejemplo,
algo cubierto en «El riesgo aceptado» de la sección de backups en `ARCHITECTURE.md`), la
respuesta es señalarlo, no necesariamente un cambio.
