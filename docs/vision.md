# Qué es esto

Panorama de conjunto: qué gobierna esta infraestructura, cómo se relaciona con los
repositorios de módulos y qué pasos separan un `git clone` de un Odoo funcional. No
repite el detalle que ya vive en otro doc — lo enlaza. El *por qué* de cada decisión
está en [`architecture.md`](architecture.md), la forma del árbol en
[`modular-architecture.md`](modular-architecture.md), las reglas en
[`../PRINCIPLES.md`](../PRINCIPLES.md), los comandos exactos en
[`entorno/levantar-produccion.md`](entorno/levantar-produccion.md).

## Qué es esta infraestructura

Un **producto**: un catálogo de stacks —contenedores— más una forma de componerlos en
un deploy, para correr Odoo autoalojado, operado por una sola persona sobre un único
servidor. El repo versiona la forma; el operador solo aporta configs.

No es un framework de propósito general ni una plataforma multi-tenant. Es la
infraestructura de **una** instancia de Odoo, pensada para que un solo operador la
levante, la entienda entera y la mantenga sin depender de un equipo.

## Dos tipos de repositorio, una sola orquestación

Este repositorio **no contiene código de aplicación**. Es infraestructura pura:
contenedores, config, scripts, `Makefile`. El código de cada módulo de Odoo —propio,
forkeado de OCA o de terceros— vive en **otro repositorio git**, uno por módulo, ajeno
a este.

La relación entre ambos es de **orquestación, no de contención**: este repo no
incorpora ese código a su propia historia — lo clona, lo actualiza y lo monta. Lo único
que sabe de cada módulo es una línea en `addons/addons.txt`: su URL y su categoría
(`enterprise` · `custom-addons` · `oca` · `third-party`, el mismo orden que resuelve el
`addons_path`). `make repo-sync` recorre ese manifiesto, clona cada repo en bare y arma
un worktree por módulo sobre la rama que declara el checkout — el mecanismo completo
está en los comentarios de [`../scripts/addons.sh`](../scripts/addons.sh). El resultado
es un árbol en disco que el contenedor de Odoo monta `:ro`; el contenedor nunca clona
nada, y el entrypoint arma el `addons_path` recorriendo ese árbol por glob.

Así, "levantar Odoo" combina siempre dos gestos distintos: `git pull` en **este**
repositorio trae una versión nueva de la infraestructura; `make repo-sync` trae el
estado más reciente de **los módulos**. Son independientes — se puede actualizar uno
sin el otro — y el detalle de por qué el código de los módulos no se hornea en la
imagen está en [`architecture.md § Gestión de addons`](architecture.md#gestión-de-addons-bind-mount).

## Cómo se levanta un Odoo funcional, de punta a punta

Nueve bloques, en orden, cada uno con su propia verificación ejecutable. El detalle
completo —comandos, qué se edita a mano, qué revisa cada `verify`— vive en
[`entorno/`](entorno/); acá solo el mapa:

| # | Bloque | Deja |
|---|---|---|
| 1 | Prerrequisitos | Cuentas de terceros (DNS, túnel, SMTP, storage de backup) y el host con Docker listo |
| 2 | Repositorio | `.env`, los secrets cargados, el daemon rotando logs |
| 3 | Edge | Certificado, reverse proxy, túnel de ingreso y DNS de la LAN |
| 4 | Database | Postgres corriendo con su tuning |
| 5 | **Addons** | `addons/addons.txt` completado, `make repo-sync` trajo el árbol de módulos, la imagen construida |
| 6 | Odoo | La aplicación sirviendo por el hostname público, sobre ese árbol |
| 7 | Backup | Snapshot probado de punta a punta, avisando por mail si falla |
| 8 | Monitoring | Métricas, logs y alertas |
| 9 | Cierre | El stack entero convergiendo de una sola vez |

El bloque 5 es la bisagra entre las dos partes de este documento: es donde el
manifiesto de módulos deja de ser una lista y se convierte en el árbol que el bloque 6
necesita para arrancar — el entrypoint de Odoo aborta si el `addons_path` queda vacío.

## Qué no es este repositorio

- No versiona código de módulos de Odoo, ni siquiera pineado por commit.
- No es el lugar para desarrollar un módulo — eso pasa en el repo de ese módulo,
  clonado como worktree bajo `addons/`; ver
  [`modulos/gestionar-modulo.md`](modulos/gestionar-modulo.md).
- No guarda datos ni estado del deployment: eso vive en volúmenes nombrados y en los
  backups, no en el checkout — un `git pull` acá nunca toca datos.
- No es específico de ningún cliente: valores que solo sirven a un deployment concreto
  —hostnames, IPs, proveedores como ejemplo obligatorio— son un defecto acá, no un
  detalle.
