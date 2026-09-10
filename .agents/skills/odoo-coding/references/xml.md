# XML Files (official, verbatim)

Source: https://www.odoo.com/documentation/19.0/es_419/contributing/development/coding_guidelines.html

Read this file when writing or editing views, actions, menus, security
records, or any other `<record>` in a module's `data/`, `views/`, or
`security/` XML files.

## Format

To declare a record in XML, the `<record>` notation is recommended:

- Place the `id` attribute before `model`
- For field declaration, the `name` attribute comes first, then the value
  (either in the field tag or the `eval` attribute), then other attributes
  (`widget`, `options`, ...) ordered by importance
- Group records by model where possible (dependencies between
  action/menu/views may make this impractical)
- Use the naming convention below
- The `<data>` tag is only for not-updatable data (`noupdate="1"`). If a file
  contains only not-updatable data, set `noupdate="1"` on the `<odoo>` tag
  directly and skip the `<data>` tag

```xml
<record id="view_id" model="ir.ui.view">
    <field name="name">view.name</field>
    <field name="model">object_name</field>
    <field name="priority" eval="16"/>
    <field name="arch" type="xml">
        <list>
            <field name="my_field_1"/>
            <field name="my_field_2" string="My Label" widget="statusbar" statusbar_visible="draft,sent,progress,done" />
        </list>
    </field>
</record>
```

Odoo supports custom tags acting as syntactic sugar, and **these are
preferred over the record notation**:

- `menuitem`: shortcut to declare an `ir.ui.menu`
- `template`: shortcut to declare a QWeb view requiring only the `arch`
  section

## XML IDs and naming

### Security, view, and action

- **Menu**: `<model_name>_menu`, or `<model_name>_menu_do_stuff` for submenus
- **View**: `<model_name>_view_<view_type>`, where `view_type` is `kanban`,
  `form`, `list`, `search`, ...
- **Action**: the main action is `<model_name>_action`; others are suffixed
  `_<detail>` (a lowercase string briefly explaining the action) - only used
  when multiple actions exist for the model
- **Window action**: suffix by the specific view info, e.g.
  `<model_name>_action_view_<view_type>`
- **Group**: `<module_name>_group_<group_name>`, where `group_name` is
  typically "user", "manager", ...
- **Rule**: `<model_name>_rule_<concerned_group>`, where `concerned_group` is
  the short name of the group ("user" for `model_name_group_user`, "public"
  for public user, "company" for multi-company rules, ...)

The `name` field should be identical to the xml id with dots replacing
underscores. Actions should have a real, human-readable name since it's used
as the display name.

```xml
<!-- views  -->
<record id="model_name_view_form" model="ir.ui.view">
    <field name="name">model.name.view.form</field>
    ...
</record>

<record id="model_name_view_kanban" model="ir.ui.view">
    <field name="name">model.name.view.kanban</field>
    ...
</record>

<!-- actions -->
<record id="model_name_action" model="ir.act.window">
    <field name="name">Model Main Action</field>
    ...
</record>

<record id="model_name_action_child_list" model="ir.actions.act_window">
    <field name="name">Model Access Children</field>
</record>

<!-- menus and sub-menus -->
<menuitem
    id="model_name_menu_root"
    name="Main Menu"
    sequence="5"
/>
<menuitem
    id="model_name_menu_action"
    name="Sub Menu 1"
    parent="module_name.module_name_menu_root"
    action="model_name_action"
    sequence="10"
/>

<!-- security -->
<record id="module_name_group_user" model="res.groups">
    ...
</record>

<record id="model_name_rule_public" model="ir.rule">
    ...
</record>

<record id="model_name_rule_company" model="ir.rule">
    ...
</record>
```

## Inheriting XML

XML IDs of inheriting views should reuse the same ID as the original record
- it helps finding all inheritance at a glance, and final XML IDs are
prefixed by the module that creates them so there is no overlap.

The `name` should contain an `.inherit.{details}` suffix so the override's
purpose is clear just from the name.

```xml
<record id="model_view_form" model="ir.ui.view">
    <field name="name">model.view.form.inherit.module2</field>
    <field name="inherit_id" ref="module1.model_view_form"/>
    ...
</record>
```

New **primary** views don't need the `.inherit` suffix, since they are new
records based on the first one:

```xml
<record id="module2.model_view_form" model="ir.ui.view">
    <field name="name">model.view.form.module2</field>
    <field name="inherit_id" ref="module1.model_view_form"/>
    <field name="mode">primary</field>
    ...
</record>
```
