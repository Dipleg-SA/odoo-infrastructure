# Crear enterprise

## Cuándo se usa

Módulo de Odoo Enterprise, sin acceso al repositorio privado de GitHub — se consume vía el ZIP que se descarga desde el portal de tu cuenta. Es la excepción al resto del modelo de addons: la licencia no permite forkear el código a una organización propia, así que no hay fork ni rama de staging ni `addons-sync`.

El mismo procedimiento sirve para instalar el módulo por primera vez y para traer una versión nueva más adelante — no hay git de por medio, así que "crear" y "actualizar" son literalmente el mismo comando.

## Objetivo

Módulo disponible en `addons/enterprise/`, instalado.

## A mano

Descargar el ZIP desde el portal de tu cuenta de Odoo.

## Comandos

```bash
unzip -q odoo-enterprise.zip -d addons/enterprise/
make odoo-install MODULES=<nombre_tecnico>   # make odoo-update si ya estaba instalado
```

`entrypoint.sh` arma el `addons_path` con un glob por categoría; no le importa si lo que hay adentro de `addons/enterprise/<módulo>/` llegó por `git worktree` o se descomprimió a mano.

## Verificación

```bash
ls addons/enterprise/<nombre_tecnico>
make odoo-modules   # confirma la versión instalada
```

---

**Sin staging por git.** Sin `addons-sync` no hay forma de traer este cambio al servidor de staging antes de producción por el camino habitual. Si querés probarlo antes de tocar producción, repetí este mismo `unzip` + `odoo-install`/`odoo-update` a mano en el checkout de staging primero — es la única forma de validarlo con este mecanismo.

La carpeta sigue gitignoreada por dentro, igual que cualquier otra categoría: el ZIP nunca se versiona.
