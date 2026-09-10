# Odoo 19 API Highlights

Version-distinguishing API patterns for Odoo 19 — what changed versus older versions (mostly 17/18), verified against the real Odoo 19.0.0 source (`odoo/orm/`, `addons/base/`, `addons/web/`). Supplements the topic guides in this folder; it does not replace them.

## Table of Contents

- [Key Changes At a Glance](#key-changes-at-a-glance)
- [Models](#models)
- [Views](#views)
- [Fields](#fields)
- [Decorators](#decorators)
- [ORM Queries](#orm-queries)
- [QWeb Templates](#qweb-templates)
- [Security](#security)
- [Quick Review Checklist (v19-specific)](#quick-review-checklist-v19-specific)

---

## Key Changes At a Glance

A one-table summary of everything detailed below — jump to the matching section for verified evidence.

| Change             | Old (Odoo 17-)                 | New (Odoo 19)                              |
| ------------------ | ------------------------------- | ------------------------------------------- |
| List view tag      | `<tree>`                       | `<list>`                                   |
| Dynamic attributes | `attrs="{'invisible': [...]}"` | `invisible="..."` (direct)                 |
| Delete validation  | Override `unlink()`            | `@api.ondelete(at_uninstall=False)`        |
| Field aggregation  | `group_operator=`              | `aggregator=`                              |
| SQL queries        | `cr.execute()`                 | `SQL` class with `execute_query_dict()`    |
| Batch create       | Single dict                    | List of dicts (`create([{...}, {...}])`)   |
| SQL constraints    | `_sql_constraints = [...]`     | `models.Constraint(...)`                   |
| DB indexes         | `index=True` only              | `models.Index(...)` declarative            |
| Kanban template    | `t-name="kanban-box"`          | `t-name="card"`                            |
| QWeb output        | `t-esc`                        | `t-out` (t-esc deprecated)                 |
| Security groups    | `category_id` on `res.groups`  | `privilege_id` + `res.groups.privilege`    |
| Private methods    | `_` prefix convention          | `@api.private` decorator (enforced)        |
| Model naming       | `_name = 'res.users'` required | CamelCase class → auto-derive `_name`      |
| read_group         | `read_group()`                 | `_read_group()` / `formatted_read_group()` |

---

## Models

### `_name` auto-derivation

`_name` can be omitted — Odoo 19 derives it from the CamelCase class name by inserting a `.` before each capital letter and lowercasing:

```python
# odoo/orm/models.py
attrs['_name'] = re.sub(r"(?<=[^_])([A-Z])", r".\1", name).lower()
```

| Class name  | Derived `_name` |
| ----------- | ---------------- |
| `ResPartner`  | `res.partner` |
| `SaleOrder`   | `sale.order`  |
| `MyModel`     | `my.model`    |

> **Verified nuance**: this works, but Odoo's own code logs a warning right after deriving it — `_logger.warning("Class %s has no _name, please make it explicit: _name = %r", ...)`. Treat an omitted `_name` as a style suggestion, not something to leave unflagged: functionally optional, but the framework itself recommends making it explicit.

### SQL constraints: `models.Constraint`, not `_sql_constraints`

The old `_sql_constraints = [(name, sql, message), ...]` list **does not exist in Odoo 19**. It was replaced by `models.Constraint(...)` assigned to a private class attribute — the attribute name (which must start with `_`) *is* the constraint's name, it is not optional or auto-generated:

```python
# real example — addons/website_event_track/models/event_track_tag.py
_name_uniq = models.Constraint(
    'unique (name)',
    'Tag name already exists!',
)
```

```python
# BAD — Odoo 19 does not read this attribute at all
_sql_constraints = [
    ('name_uniq', 'unique (name)', 'Tag name already exists!'),
]
```

### Database indexes: `models.Index`

New in Odoo 19 — declarative indexes as class attributes, same naming rule as `Constraint` (attribute name starts with `_`):

```python
# real example — addons/sale/models/sale_order.py
_date_order_id_idx = models.Index("(date_order desc, id desc)")
```

Reference: `references/odoo-19-model-guide.md`.

---

## Views

Same as 18: `<list>` tag (not `<tree>`), direct-expression attributes (`invisible="state == 'done'"`, not `attrs="{...}"`). Verified: zero `<tree>` tags remain in `addons/base/views/`.

Reference: `references/odoo-19-view-guide.md`.

---

## Fields

Same as 18: `aggregator=` for aggregation, not `group_operator=`. Confirmed by the deprecation warning in `odoo/orm/fields.py`: *"Since Odoo 18, 'group_operator' is deprecated, use 'aggregator' instead"*.

Reference: `references/odoo-19-field-guide.md`.

---

## Decorators

Same as 18: `@api.ondelete(at_uninstall=...)`, `@api.model_create_multi`, `@api.private`. All three confirmed present in `odoo/orm/decorators.py`.

`@api.model_create_multi` accepts either a single dict or a list of dicts — it's not that single-dict `create()` calls stop working, it's that the *implementation* should be written to handle a list efficiently:

```python
@api.model_create_multi
def create(self, vals_list):
    ...  # vals_list is always a list here, even if the caller passed a single dict
```

> **`@api.returns` does not exist in Odoo 19** — it is not defined in `odoo/orm/decorators.py` and is not exported from `odoo/api/__init__.py`. Using it raises `AttributeError: module 'odoo.api' has no attribute 'returns'`. It was removed, not "expanded" — do not suggest it.

Reference: `references/odoo-19-decorator-guide.md`.

---

## ORM Queries

### Raw SQL: use the `SQL` class

```python
from odoo.tools import SQL

rows = self.env.execute_query(SQL("SELECT id FROM sale_order WHERE state = %s", 'draft'))
rows_as_dicts = self.env.execute_query_dict(SQL("SELECT id, name FROM sale_order WHERE state = %s", 'draft'))
```

Both `execute_query` and `execute_query_dict` are confirmed on `Environment` (`odoo/orm/environments.py`). Never build SQL with string concatenation or f-strings — see `references/odoo-19-security-guide.md` for the injection pitfalls.

### `read_group()` is deprecated, not removed

`read_group()` still exists and still works — its own docstring says `"""Deprecated - Get the list of records..."""`. Prefer `_read_group()` (private, returns tuples) or `formatted_read_group()` (returns dicts) in new code; don't flag existing `read_group()` calls as broken, but do suggest migrating them.

Reference: `references/odoo-19-model-guide.md`, `references/odoo-19-performance-guide.md`.

---

## QWeb Templates

`t-esc` is deprecated in favor of `t-out`. Confirmed by the runtime warning in `addons/base/models/ir_qweb.py`: *"Found deprecated directive @t-esc=%r in template %r. Replace by @t-out"*.

Kanban card templates use `t-name="card"`, not the old `t-name="kanban-box"` — confirmed in `addons/web/static/`.

Reference: `references/odoo-19-view-guide.md`, `references/odoo-19-reports-guide.md`.

---

## Security

`category_id` was removed from `res.groups`, replaced by `privilege_id` referencing the new `res.groups.privilege` model. Full detail (3-tier architecture, migration example) already lives in `references/odoo-19-security-guide.md` — this entry exists only so `reviewer`/`tracer` know it's a v19-specific breaking change worth flagging when they see `category_id` on a group record.

---

## Quick Review Checklist (v19-specific)

- ✅ `_name` may be omitted when the CamelCase class name maps correctly — flag as a **style suggestion** (Odoo itself warns about it), not as an error.
- ❌ `_sql_constraints = [...]` — flag as **incorrect for Odoo 19**; suggest `models.Constraint(...)` instead.
- ❌ `@api.returns` — flag as **does not exist in Odoo 19**; remove or find the actual replacement for the intent (usually unnecessary — return types are inferred by callers).
- ❌ `<tree>` view tag, `attrs="{...}"` — flag as deprecated; use `<list>` and direct-expression attributes.
- ❌ `group_operator=` on a field — flag as deprecated; use `aggregator=`.
- ❌ `t-esc` in QWeb templates — flag as deprecated; use `t-out`.
- ⚠️ `read_group()` calls — not broken, but deprecated; suggest `_read_group()`/`formatted_read_group()` for new code.
- ❌ `category_id` on a `res.groups` record — flag as removed in v19; use `privilege_id` + `res.groups.privilege`.
- ✅ Raw SQL should use `odoo.tools.SQL` with `env.execute_query()`/`execute_query_dict()`, never string concatenation.

---

## References

- Verified against `.repos/odoo` (community, `version_info = (19, 0, 0, FINAL, 0, '')`), specifically `odoo/orm/models.py`, `odoo/orm/fields.py`, `odoo/orm/decorators.py`, `odoo/orm/table_objects.py`, `odoo/orm/environments.py`, `addons/base/models/ir_qweb.py`, `addons/base/views/`.
- [Odoo 19 Official Documentation](https://github.com/odoo/documentation/tree/19.0)
