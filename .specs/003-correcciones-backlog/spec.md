# Especificación: Correcciones integrales del backlog

| Nombre | Código | Versión | Fecha | Estado |
| --- | --- | --- | --- | --- |
| Correcciones integrales del backlog | SPEC-003 | R00 | 2026-09-17 | Converged |

## Resumen

Cerrar los 41 ítems pendientes del backlog alineando contratos, documentación,
operación, seguridad, especificaciones y pruebas con la arquitectura vigente del
repositorio.

## Aclaraciones

| Nombre | Versión | Fecha |
| --- | --- | --- |
| Correcciones integrales del backlog | R00 | 2026-09-17 |

### Sesión 2026-09-17

- Q: ¿`addons-webhook` debe recibir targets de ciclo de vida propios en Make o permanecer como fragmento de control verificable solo mediante el orquestador? → A: Debe recibir targets propios de Make, igual que los demás contenedores; el orquestador global conserva las operaciones sobre el conjunto completo.

## Métricas de éxito

- Backlog pendiente: 0 ítems abiertos entre B001 y B041 al finalizar la ejecución.
- Referencias legacy activas: 0 referencias operativas a `envs/`, `.env` raíz,
  `addons/addons.txt` o `state/` raíz, salvo compatibilidad documentada y probada.
- Regresiones: `make test` y las verificaciones específicas de los cambios terminan
  correctamente en cada lote.
- Hermeticidad: ejecutar `make test` no elimina ni modifica datos preexistentes bajo
  `runtime/`, `state/`, secretos ni checkouts privados.

## Historias de usuario

### US1 — Mantener contratos y documentación vigentes (P1)

Como operador, quiero que la documentación, los principios, el inventario y los
artefactos de especificación describan las rutas y operaciones reales, para poder
seguir un procedimiento sin recurrir al diseño anterior.

**Escenarios de aceptación**:

- **Dado** un documento operativo o de arquitectura vigente, **cuando** se busca el
  modelo anterior, **entonces** no contiene instrucciones ejecutables basadas en
  `envs/`, `.env` raíz, `addons/addons.txt`, ZIP Enterprise o `state/` raíz.
- **Dado** el modelo actual, **cuando** se documenta una selección de edición,
  **entonces** solo se utilizan `ODOO_EDITION` y `TAG` en el `compose.env` del runtime.
- **Dado** el inventario de stacks y sus targets, **cuando** se consulta la ayuda o la
  arquitectura, **entonces** `addons-webhook` tiene targets propios de Make equivalentes
  a los demás contenedores, y `repo-sync` y `repo-status` tienen un ciclo de vida
  explícito sin agrupaciones vacías.
- **Dado** el repositorio, **cuando** se revisan sus artefactos de entrega, **entonces**
  el registro de cambios se realiza en el release y no mediante un changelog versionado.
- **Dado** un backlog compartido, **cuando** otro checkout lo obtiene, **entonces** sus
  ítems están disponibles en `.specs/backlog.md`.

### US2 — Operar con límites seguros y consistentes (P1)

Como operador, quiero que las comprobaciones y operaciones respeten el entorno, los
permisos, los perfiles y los límites de cada servicio, para evitar acciones sobre otro
runtime o falsos estados saludables.

**Escenarios de aceptación**:

- **Dado** una configuración de host o notificación inválida, **cuando** se ejecuta su
  verificación, **entonces** falla antes de declarar el host listo y entrega una
  corrección accionable.
- **Dado** un comando de addons, dependencias, integridad o operación one-off,
  **cuando** falta el entorno o existe otro checkout concurrente, **entonces** falla o
  se serializa sin usar rutas, locks ni nombres globales ambiguos.
- **Dado** un runtime Community, **cuando** se ejecuta un build o una operación de
  dependencias, **entonces** no recurre a las rutas legacy ni incorpora Enterprise
  residual.
- **Dado** un servicio que requiere acceso privilegiado, **cuando** se construye o se
  verifica su composición, **entonces** el permiso queda limitado a lo necesario,
  documentado y cubierto por una comprobación.
- **Dado** una retención, perfil o fragmento de Compose opcional, **cuando** se cambia
  o se verifica, **entonces** la configuración efectiva y la expectativa del verificador
  coinciden incluso si el perfil está inactivo.

### US3 — Conservar una suite confiable y reproducible (P1)

Como mantenedor, quiero que los tests detecten regresiones reales sin destruir el
estado local ni depender únicamente de stubs, para poder ejecutarlos antes de integrar
cambios.

**Escenarios de aceptación**:

- **Dado** un checkout con estado ignorado preexistente, **cuando** se ejecuta `make
  test`, **entonces** el estado permanece byte a byte igual al finalizar la suite.
- **Dado** cada `stacks/<nombre>/verify.sh`, **cuando** se rompe una expectativa propia,
  **entonces** existe una prueba que falla por esa ruptura y el orquestador conserva la
  diferencia entre stack ausente y servicio caído.
- **Dado** un stub sin fixture esperado, **cuando** una prueba lo invoca, **entonces** el
  stub falla explícitamente en vez de devolver éxito implícito.
- **Dado** una imagen Odoo o una configuración de herramienta, **cuando** se ejecuta el
  smoke test correspondiente, **entonces** se valida al menos una vez el comportamiento
  real de Docker o del binario de la herramienta, separado de la suite sin daemon.
- **Dado** un comando auxiliar de preparación o un parser de configuración, **cuando**
  falla o cambia la estructura, **entonces** la prueba informa el fallo y no queda verde
  por una aserción textual incompleta.

### US4 — Mantener trazabilidad del trabajo de Spec-Flow (P2)

Como colaborador, quiero que los specs, planes, tareas y backlog indiquen su estado
real y usen una convención uniforme, para saber qué está aprobado, convergido o todavía
pendiente.

**Escenarios de aceptación**:

- **Dado** un artefacto de una feature finalizada, **cuando** se compara su estado con
  sus tareas, **entonces** no declara `Approved` si la ejecución ya fue convergida ni
  marca como completa una tarea que conserva `partial` o `missing`.
- **Dado** un artefacto nuevo bajo `.specs`, **cuando** se revisa su formato, **entonces**
  mantiene idioma, nombres de fases y estructura homogéneos.
- **Dado** una especificación histórica, **cuando** conserva rutas antiguas por razones
  de contexto, **entonces** está identificada como histórica y no se presenta como
  instrucción vigente.

## Requisitos no funcionales

- **MUST**: Ninguna corrección debe modificar secretos, archivos privados de
  `runtime/*/compose.env`, datos de Docker, checkouts Enterprise o estado operativo
  preexistente sin una acción explícita del operador.
- **MUST**: Cada lote debe poder verificarse con `make test`, `bash -n` y las
  comprobaciones específicas que correspondan, sin exigir red ni un daemon Docker salvo
  en smoke tests separados.
- **MUST**: La implementación debe conservar los verbos operativos existentes o
  documentar cualquier cambio de interfaz antes de aplicarlo.
- **SHOULD**: Las correcciones deben entregarse en commits separados por frente para
  facilitar revisión y reversión.

## Casos límite

- Un checkout antiguo puede conservar datos bajo `state/` o `runtime/`; la migración
  debe detectarlos sin borrarlos automáticamente.
- `addons-webhook` continúa incluido como fragmento de control en la composición que
  corresponda, pero sus operaciones puntuales también deben estar disponibles mediante
  targets propios de Make y quedar probadas.
- Certbot, dnsmasq y restore pueden estar declarados pero inactivos por perfil; su
  ausencia de ejecución no debe convertirse en un falso positivo.
- El repositorio puede conservar estados históricos de Spec-Flow, pero no debe mezclar
  documentación histórica con instrucciones vigentes.

## Supuestos y dependencias

- `.specs/constitution.md` permanece como contrato global del repositorio.
- Las correcciones se aplican sobre la arquitectura actual bajo `runtime/`, `stacks/`
  y `tests/`.
- La política del repositorio no utiliza `CHANGELOG.md`; los cambios se registran en
  los releases.
- La ejecución se divide en lotes y cada lote pasa por su propio plan, tareas,
  implementación, convergencia y commit.

## No objetivos explícitos

- No rediseñar la arquitectura de runtimes, stacks, backups o gestión de addons fuera
  de los límites ya identificados en el backlog.
- No ejecutar migraciones funcionales de módulos Odoo automáticamente.
- No borrar datos ignorados del operador para hacer pasar una prueba.
- No crear un sistema de changelog paralelo al release.
