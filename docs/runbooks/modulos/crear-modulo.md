# Crear módulo

## Cuándo se usa

Ya tenés un repositorio declarado y sincronizado (ver [crear-fork](crear-fork.md)) y necesitás un módulo nuevo adentro. Es el mismo procedimiento sin importar el origen del repositorio contenedor — un módulo nuevo dentro de tu propio repo o dentro de un fork de terceros nace igual.

No aplica a Odoo Enterprise sin acceso git — ver [crear-enterprise](crear-enterprise.md).

## Objetivo

Módulo con el esqueleto generado, instalado y corriendo en tu entorno de desarrollo.

## A mano

Decidir el nombre técnico (`snake_case`). Tenelo presente contra la precedencia entre categorías si otro módulo en otra categoría ya usa ese nombre (ver la nota al final de [crear-fork](crear-fork.md)).

## Comandos

```bash
cd addons/<categoría>/<repo> && git checkout -b feat/<nombre-del-modulo> && cd -
```

**Generar el esqueleto directo en `addons/<categoría>/<repo>/<nombre_tecnico>/`** — archivos de host, sin Docker: el mount de `/mnt/extra-addons` es read-only adentro del contenedor, pero eso nunca frenó al host, y la plantilla no depende de nada que solo exista dentro de la imagen.

```
<nombre_tecnico>/
├── __init__.py             # from . import models
├── __manifest__.py
├── models/__init__.py      # vacío hasta que haya un modelo real
├── views/                  # vacío hasta la primera vista
├── security/ir.model.access.csv   # solo el header, sin filas hasta que exista un modelo
└── data/                   # vacío hasta el primer dato
```

Deliberadamente sin `controllers/` ni `demo/` — se agregan cuando el módulo los necesita, no antes — y sin modelo de ejemplo: arrancar de un `models/__init__.py` vacío evita limpiar después un modelo mal nombrado.

`__manifest__.py` con datos reales, no placeholders:

```python
{
    'name': "<Nombre legible>",
    'summary': "<una línea real>",
    'author': "<tu organización>",
    'category': '<categoría>',
    'version': '1.0.0',
    'license': 'LGPL-3',
    'depends': ['base'],   # lo que corresponda — sin adivinar
    'data': [
        # 'security/ir.model.access.csv',
    ],
}
```

```bash
make odoo-install MODULES=<nombre_tecnico>
```

## Verificación

```bash
make odoo-modules   # <nombre_tecnico> aparece instalado
make addons         # el repo está en feat/<nombre-del-modulo>, limpio
```

---

De acá en más, cualquier cambio a este módulo —incluida la primera vez que se instala en staging o en producción— sigue [actualizar-modulo](actualizar-modulo.md).
