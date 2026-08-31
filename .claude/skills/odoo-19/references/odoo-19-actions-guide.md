# Odoo 19 Actions Guide

Guide for working with Odoo 19 actions (`ir.actions.*`), scheduled jobs (cron), and action bindings.

## Table of Contents
- [Action Types](#action-types)
- [Window Actions](#window-actions)
- [Server Actions](#server-actions)
- [Report Actions](#report-actions)
- [Client Actions](#client-actions)
- [URL Actions](#url-actions)
- [Scheduled Actions (Cron)](#scheduled-actions-cron)
- [Action Bindings](#action-bindings)

---

## Action Types

Actions define the behavior of the system in response to user actions: login, action button, selection of records, etc.

Actions can be stored in the database or returned directly as dictionaries. All actions share two mandatory attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `type` | string | The category of the current action |
| `name` | string | Short user-readable description |

A client can get actions in 4 forms:
- `False` - closes any open action dialog
- A string - client action tag or number
- A number - database identifier or external ID
- A dictionary - client action descriptor

---

## Window Actions

`ir.actions.act_window` - The most common action type, used to present visualizations of a model through views.

### Key Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `res_model` | string | Model to present views for |
| `views` | list | List of `(view_id, view_type)` pairs |
| `res_id` | int | If default view is `form`, specifies the record to load |
| `search_view_id` | tuple | `(id, name)` pair for specific search view |
| `target` | string | `current`, `fullscreen`, `new`, or `main` |
| `context` | dict | Additional context data |
| `domain` | list | Filtering domain |
| `limit` | int | Number of records to display (default: 80) |

### Example: Opening customers

```python
{
    "type": "ir.actions.act_window",
    "res_model": "res.partner",
    "views": [[False, "list"], [False, "form"]],
    "domain": [["customer", "=", True]],
}
```

### Example: Opening specific product in dialog

```python
{
    "type": "ir.actions.act_window",
    "res_model": "product.product",
    "views": [[False, "form"]],
    "res_id": a_product_id,
    "target": "new",
}
```

### In-Database Fields

When defining actions from XML data files:

| Attribute | Description |
|-----------|-------------|
| `view_mode` | Comma-separated list of view types (e.g., `list,form`) |
| `view_ids` | Many2many to view objects |
| `view_id` | Specific view to add to views list |

### Using ir.actions.act_window.view

```xml
<record model="ir.actions.act_window.view" id="test_action_tree">
   <field name="sequence" eval="1"/>
   <field name="view_mode">list</field>
   <field name="view_id" ref="view_test_tree"/>
   <field name="act_window_id" ref="test_action"/>
</record>
```

---

## Server Actions

`ir.actions.server` - Allow triggering complex server code from any valid action location.

### Key Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | int | In-database identifier |
| `model_id` | ref | Odoo model linked to the action |
| `state` | string | Type of action: `code`, `object_create`, `object_write`, `object_copy`, `webhook`, `multi` |
| `code` | string | Python code to execute |

### State: code

```xml
<record model="ir.actions.server" id="print_instance">
    <field name="name">Res Partner Server Action</field>
    <field name="model_id" ref="model_res_partner"/>
    <field name="state">code</field>
    <field name="code">
        raise UserError(record.name)
    </field>
</record>
```

### Returning next action

```xml
<record model="ir.actions.server" id="open_form">
    <field name="name">Open Form Action</field>
    <field name="model_id" ref="model_res_partner"/>
    <field name="state">code</field>
    <field name="code">
        if record.some_condition():
            action = {
                "type": "ir.actions.act_window",
                "view_mode": "form",
                "res_model": record._name,
                "res_id": record.id,
            }
    </field>
</record>
```

### State: object_create

| Attribute | Description |
|-----------|-------------|
| `crud_model_id` | Model in which to create a new record (defaults to the action's own model if unset) |
| `link_field_id` | Many2one field on which to set the newly created record |

> **Verified against `ir_actions.py`**: there is no `fields_lines` field in Odoo 19 (it only survives as an orphaned string in old `.po` translation files). The value(s) to set are configured through `update_field_id` (field to set), `update_path` (dotted path, e.g. `partner_id.name`), `value` / `html_value` / `resource_ref` / `selection_value` (depending on the field type), `evaluation_type` (`value`, `sequence`, or `equation`), and `update_m2m_operation` (`add`, `remove`, `set`, `clear` — for many2many fields).

### State: object_write

Updates the current record(s). Same attribute set as `object_create` above (`update_field_id`, `update_path`, `value`, `evaluation_type`, `update_m2m_operation`) — **not** `fields_lines`.

### State: object_copy

Duplicates the current record(s). No dedicated attributes beyond `state`.

### State: webhook

Sends a POST request to an external system when the action runs.

| Attribute | Description |
|-----------|-------------|
| `webhook_url` | URL to send the POST request to |
| `webhook_field_ids` | Fields to include in the POST payload (the record's `id` and `model` are always sent as `_id`/`_model`; the action name is always sent as `_name`) |

### State: multi

Executes several actions given through `child_ids`.

### Evaluation Context

Available variables in server actions:
- `model` - Model object linked to the action
- `record`/`records` - Record/recordset on which the action is triggered
- `env` - Odoo Environment
- `uid`, `user` - Current user id and record
- `datetime`, `dateutil`, `time`, `timezone` - Python modules
- `float_compare`, `b64encode`, `b64decode`, `Command` - Helper functions
- `log(message, level='info')` - Logging function
- `UserError` - Exception class for user-facing errors

> **Verified against `ir_actions.py:_get_eval_context`**: `Warning` is **not** part of the eval context — `UserError` is what's actually injected. `raise Warning(...)` is a stale pattern from very old Odoo versions; use `raise UserError(...)` instead (see the `State: code` example above).

---

## Report Actions

`ir.actions.report` - Triggers the printing of a report.

### Key Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Used as file name if `print_report_name` not specified |
| `model` | string | Model your report will be about |
| `report_type` | string | `qweb-pdf` or `qweb-html` |
| `report_name` | string | External ID of the qweb template |
| `print_report_name` | string | Python expression for report name |
| `groups_id` | Many2many | Groups allowed to view/use the report |
| `multi` | boolean | If True, not displayed on form view |
| `paperformat_id` | Many2one | Paper format to use |
| `attachment_use` | boolean | Generate once, then reprint from stored report |
| `attachment` | string | Python expression for attachment name |

### Print Menu Integration

If you define your report through a `<record>` and want it in the Print menu:

```xml
<record id="my_report" model="ir.actions.report">
    <field name="name">My Report</field>
    <field name="model">my.model</field>
    <field name="report_type">qweb-pdf</field>
    <field name="report_name">my_module.my_template</field>
    <field name="binding_model_id" ref="model_my_model"/>
</record>
```

---

## Client Actions

`ir.actions.client` - Triggers an action implemented entirely in the client.

### Key Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `tag` | string | Client-side identifier of the action |
| `params` | dict | Additional data to send to the client |
| `target` | string | `current`, `new`, `fullscreen`, or `main` |

```python
{
    "type": "ir.actions.client",
    "tag": "pos.ui"
}
```

Tells the client to start the Point of Sale interface.

---

## URL Actions

`ir.actions.act_url` - Allow opening a URL (website/web page).

### Key Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `url` | string | The address to open |
| `target` | string | `new`, `self`, or `download` |

```python
{
    "type": "ir.actions.act_url",
    "url": "https://odoo.com",
    "target": "self",
}
```

---

## Scheduled Actions (Cron)

`ir.cron` - Actions triggered automatically on a predefined frequency.

### Key Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Name of the scheduled action |
| `interval_number` | int | Number of interval_type units between executions |
| `interval_type` | string | `minutes`, `hours`, `days`, `weeks`, `months` |
| `model_id` | ref | Model on which this action will be called |
| `code` | string | Code content of the action |
| `nextcall` | datetime | Next planned execution date |
| `priority` | int | Priority when executing multiple actions |

### Writing cron functions

When writing cron functions, batch the progress to avoid blocking workers:

```python
def _cron_do_something(self, *, limit=300):
    domain = [('state', '=', 'ready')]
    records = self.search(domain, limit=limit)
    records.do_something()
    # notify progression
    remaining = 0 if len(records) == limit else self.search_count(domain)
    self.env['ir.cron']._commit_progress(len(records), remaining=remaining)
```

### Managing resources between batches

```python
def _cron_do_something(self):
    assert self.env.context.get('cron_id'), "Run only inside cron jobs"
    domain = [('state', '=', 'ready')]
    records = self.search(domain)
    self.env['ir.cron']._commit_progress(remaining=len(records))

    with open_some_connection() as conn:
        for record in records:
            record = record.try_lock_for_update().filtered_domain(domain)
            if not record:
                continue
            try:
                record.do_something(conn)
                if not self.env['ir.cron']._commit_progress(1):
                    break
            except Exception:
                self.env.cr.rollback()
```

### Running cron functions

Do not call cron functions directly. Use:
- `IrCron.method_direct_trigger()` - for testing
- `IrCron._trigger()` - for scheduled execution

### Security Measures

- If it fails **5 consecutive times** (`MIN_FAILURE_COUNT_BEFORE_DEACTIVATION`) with the first failure being at least **7 days** old (`MIN_DELTA_BEFORE_DEACTIVATION`), the cron is deactivated (`active = False`) and the DB admin is notified. A success at any point resets both counters.
- A hard-limit exists for cron execution at the database level

> **Verified against `ir_cron.py`**: there is no separate "skip after 3 consecutive failures" mechanism — only the 5-failures/7-days deactivation rule above exists.

---

## Action Bindings

Actions can be bound to models to appear in contextual menus.

### Binding Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `binding_model_id` | Many2one | Model the action is bound to (use `model_id` for Server Actions) |
| `binding_type` | string | `action` (default) or `report` |
| `binding_view_types` | string | Comma-separated list: `list`, `form`, or `list,form` (default) |

### Binding Type: action

Action appears in the **Action** contextual menu.

### Binding Type: report

Action appears in the **Print** contextual menu.

---

## References

- Source: Odoo 19 documentation `/doc/developer/reference/backend/actions.rst`
- Verified against `.repos/odoo` (community, `version_info = (19, 0, 0, FINAL, 0, '')`): `odoo/addons/base/models/ir_actions.py`, `odoo/addons/base/models/ir_actions_report.py`, `odoo/addons/base/models/ir_cron.py`, `odoo/orm/models.py`.
