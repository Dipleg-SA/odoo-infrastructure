---
name: odoo-coding
description: >
  Guides Odoo-style code following official Odoo coding guidelines: module
  directory/file layout, XML record and ID conventions, Python idioms and
  model/method naming, JS static-file organization, and SCSS/CSS naming and
  variable conventions. This skill should be used whenever the user asks to
  write, add, or review a model, view, controller, wizard, report, widget,
  or stylesheet in a repository that looks like Odoo (an
  `__manifest__.py`/addons layout, or existing files following these
  conventions) - even if they just say "add a field to this model" or
  "create a new view" without mentioning Odoo by name. Takes priority over
  generic language style guides once the repo is recognized as Odoo-style.
---

## Before editing existing files

- **Stable version**: never restyle an existing file to match these
  guidelines - the original file's style strictly supersedes them. Keep the
  diff minimal; it protects the file's revision history.
- **Master/development version**: only apply these guidelines to *modified*
  code, or to a file's whole structure if it's already undergoing a major
  rewrite. If a real restructuring is warranted, do a move commit first (see
  the sibling `odoo-commit` skill's `[MOV]` tag), then a separate commit for
  the actual change - never both at once.

## Module layout

- `data/` - demo/data xml
- `models/` - model definitions
- `controllers/` - HTTP routes
- `views/` - views and templates
- `static/` - web assets (`css/`, `js/`, `img/`, `lib/`, ...)
- `wizard/` - transient models (`models.TransientModel`) and their views
- `report/` - printable reports and SQL-view-based models
- `tests/` - Python tests

File names: lowercase `[a-z0-9_]` only. For the full per-directory file
naming convention (which file a new model/view/wizard/report belongs in, the
community module naming prefix, file permissions, and the complete example
tree), read `references/module-structure.md`.

## Which reference to read

| Editing... | Read |
|---|---|
| `models/`, `controllers/`, `wizard/`, `report/*.py` (Python) | `references/python.md` |
| `views/`, `data/`, `security/*.xml` (groups, rules), `report/*.xml` (report actions, QWeb templates) | `references/xml.md` |
| `security/ir.model.access.csv` (naming only - format isn't covered by the official page) | `references/module-structure.md` |
| `static/src/js/`, `static/src/xml/` (QWeb templates for JS widgets) | `references/javascript.md` |
| `static/src/scss/` (or `.css`) | `references/css-scss.md` |
| Where a new file belongs / how to name it | `references/module-structure.md` |

Each reference holds the complete official rules and examples for its
domain - read only the one(s) relevant to the file being touched, not all of
them.

## Related skill

For drafting the commit message once the change is ready, and for the
`[TAG]`/module conventions used above, see the sibling `odoo-commit` skill.
