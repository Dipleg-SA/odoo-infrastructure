# Module Structure (official, verbatim)

Source: https://www.odoo.com/documentation/19.0/es_419/contributing/development/coding_guidelines.html
(Odoo 19.0 documentation - content is identical between the es_419 and default English pages)

Read this file when deciding where a new file belongs in a module, or what
to name it.

> **Warning (official):** For modules developed by the community, it is
> strongly recommended to name your module with a prefix like your company
> name.

## Directories

- `data/` - demo and data xml
- `models/` - models definition
- `controllers/` - contains controllers (HTTP routes)
- `views/` - contains the views and templates
- `static/` - contains the web assets, separated into `css/`, `js/`, `img/`,
  `lib/`, ...

Other optional directories:

- `wizard/` - regroups the transient models (`models.TransientModel`) and
  their views
- `report/` - contains the printable reports and models based on SQL views.
  Python objects and XML views are included in this directory
- `tests/` - contains the Python tests

## File naming

Example module used throughout: a plant nursery application holding two main
models, `plant.nursery` and `plant.order`.

**Models** - split business logic by sets of models belonging to the same
main model. Each set lives in a file named after its main model. If there is
only one model, its name matches the module name. Each inherited model
should be in its own file.

```
addons/plant_nursery/
|-- models/
|   |-- plant_nursery.py (first main model)
|   |-- plant_order.py (another main model)
|   |-- res_partner.py (inherited Odoo model)
```

**Security** - three main files:

- Access rights: `ir.model.access.csv`
- User groups: `<module>_groups.xml`
- Record rules: `<model>_security.xml`

```
addons/plant_nursery/
|-- security/
|   |-- ir.model.access.csv
|   |-- plant_nursery_groups.xml
|   |-- plant_nursery_security.xml
|   |-- plant_order_security.xml
```

**Views** - backend views (list, form, kanban, activity, graph, pivot, ...)
are split like models and suffixed `_views.xml`. Main menus not tied to a
specific action may be extracted into an optional `<module>_menus.xml`.
Templates (QWeb pages, notably for portal/website display) go in separate
files named `<model>_templates.xml`.

```
addons/plant_nursery/
|-- views/
|   |-- plant_nursery_menus.xml (optional definition of main menus)
|   |-- plant_nursery_views.xml (backend views)
|   |-- plant_nursery_templates.xml (portal templates)
|   |-- plant_order_views.xml
|   |-- plant_order_templates.xml
|   |-- res_partner_views.xml
```

**Data** - split by purpose (demo or data) and main model:
`<main_model>_demo.xml` or `<main_model>_data.xml`.

```
addons/plant_nursery/
|-- data/
|   |-- plant_nursery_data.xml
|   |-- plant_nursery_demo.xml
|   |-- mail_data.xml
```

**Controllers** - generally all controllers belong to a single file named
`<module_name>.py` (the old `main.py` convention is deprecated). If
inheriting an existing controller from another module, use
`<inherited_module_name>.py` (e.g. `portal.py`).

```
addons/plant_nursery/
|-- controllers/
|   |-- plant_nursery.py
|   |-- portal.py (inheriting portal/controllers/portal.py)
|   |-- main.py (deprecated, replaced by plant_nursery.py)
```

**Static files** - JavaScript files follow the same logic as Python models:
each component in its own meaningfully-named file, with subdirectories for
larger "packages" if needed. Same logic applies to JS widget templates
(static XML files) and styles (scss files). Don't link data (images,
libraries) outside Odoo - copy them into the codebase instead of using an
external URL.

**Wizards** - naming convention mirrors Python models: `<transient>.py` and
`<transient>_views.xml`, both inside `wizard/`.

```
addons/plant_nursery/
|-- wizard/
|   |-- make_plant_order.py
|   |-- make_plant_order_views.xml
```

**Statistics reports** (Python/SQL views + classic views):

```
addons/plant_nursery/
|-- report/
|   |-- plant_order_report.py
|   |-- plant_order_report_views.xml
```

**Printable reports** (data preparation + QWeb templates):

```
addons/plant_nursery/
|-- report/
|   |-- plant_order_reports.xml (report actions, paperformat, ...)
|   |-- plant_order_templates.xml (xml report templates)
```

## Complete module tree

```
addons/plant_nursery/
|-- __init__.py
|-- __manifest__.py
|-- controllers/
|   |-- __init__.py
|   |-- plant_nursery.py
|   |-- portal.py
|-- data/
|   |-- plant_nursery_data.xml
|   |-- plant_nursery_demo.xml
|   |-- mail_data.xml
|-- models/
|   |-- __init__.py
|   |-- plant_nursery.py
|   |-- plant_order.py
|   |-- res_partner.py
|-- report/
|   |-- __init__.py
|   |-- plant_order_report.py
|   |-- plant_order_report_views.xml
|   |-- plant_order_reports.xml (report actions, paperformat, ...)
|   |-- plant_order_templates.xml (xml report templates)
|-- security/
|   |-- ir.model.access.csv
|   |-- plant_nursery_groups.xml
|   |-- plant_nursery_security.xml
|   |-- plant_order_security.xml
|-- static/
|   |-- img/
|   |   |-- my_little_kitten.png
|   |   |-- troll.jpg
|   |-- lib/
|   |   |-- external_lib/
|   |-- src/
|   |   |-- js/
|   |   |   |-- widget_a.js
|   |   |   |-- widget_b.js
|   |   |-- scss/
|   |   |   |-- widget_a.scss
|   |   |   |-- widget_b.scss
|   |   |-- xml/
|   |   |   |-- widget_a.xml
|   |   |   |-- widget_b.xml
|-- views/
|   |-- plant_nursery_menus.xml
|   |-- plant_nursery_views.xml
|   |-- plant_nursery_templates.xml
|   |-- plant_order_views.xml
|   |-- plant_order_templates.xml
|   |-- res_partner_views.xml
|-- wizard/
|   |-- make_plant_order.py
|   |-- make_plant_order_views.xml
```

> **Note (official):** File names should only contain `[a-z0-9_]` (lowercase
> alphanumerics and `_`).

> **Warning (official):** Use correct file permissions: folder `755` and
> file `644`.
