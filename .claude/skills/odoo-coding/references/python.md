# Python (official, verbatim)

Source: https://www.odoo.com/documentation/19.0/es_419/contributing/development/coding_guidelines.html

Read this file when writing or editing Python code in `models/`,
`controllers/`, or `wizard/`.

> **Warning (official):** Also read the Security Pitfalls guidance
> (separate Odoo documentation page, not part of this reference) before
> writing code that touches access rights, `sudo()`, or user input.

## PEP8 options

A linter helps show syntax/semantic warnings. Odoo source code tries to
respect the Python standard, but some rules can be ignored:

- `E501`: line too long
- `E301`: expected 1 blank line, found 0
- `E302`: expected 2 blank lines, found 1

## Imports

Imports are ordered in three groups, each alphabetically sorted inside
itself:

1. External libraries (one per line, sorted, split from python stdlib)
2. Imports of Odoo submodules
3. Imports from Odoo addons (rarely, and only if necessary)

```python
# 1 : imports of python lib
import base64
import re
import time
from datetime import datetime
# 2 : imports of odoo
from odoo import Command, _, api, fields, models # ASCIIbetically ordered
from odoo.fields import Domain
from odoo.tools.safe_eval import safe_eval as eval
# 3 : imports from odoo addons
from odoo.addons.web.controllers.main import login_redirect
from odoo.addons.website.models.website import slug
```

## Idiomatics of Programming (Python)

Always favor readability over conciseness or clever use of language
features.

**Don't use `.clone()`:**

```python
# bad
new_dict = my_dict.clone()
new_list = old_list.clone()
# good
new_dict = dict(my_dict)
new_list = list(old_list)
```

**Dictionary creation and update:**

```python
# -- creation empty dict
my_dict = {}
my_dict2 = dict()

# -- creation with values
# bad
my_dict = {}
my_dict['foo'] = 3
my_dict['bar'] = 4
# good
my_dict = {'foo': 3, 'bar': 4}

# -- update dict
# bad
my_dict['foo'] = 3
my_dict['bar'] = 4
my_dict['baz'] = 5
# good
my_dict.update(foo=3, bar=4, baz=5)
my_dict = dict(my_dict, **my_dict2)
```

**Use meaningful variable/class/method names.** Avoid pointless temporary
variables:

```python
# pointless
schema = kw['schema']
params = {'schema': schema}
# simpler
params = {'schema': kw['schema']}
```

**Multiple return points are OK, when they're simpler:**

```python
# clearer
def axes(self, axis):
    if type(axis) == type([]):
        return list(axis) # clone the axis
    else:
        return [axis] # single-element list
```

**Know the builtins** - e.g. `my_dict.get('key')` beats
`my_dict.get('key', None)`. Also, `'key' in my_dict` and
`my_dict.get('key')` mean different things - use the right one.

**Use list/dict comprehensions**, `map`, `filter`, `sum`, etc. - they make
code easier to read:

```python
# better
cube = [(i['id'], i['name']) for i in res]
```

**Collections are booleans too** - empty collections are falsy, non-empty
ones truthy: `bool([])` is `False`, `bool([1])` is `True`. Prefer
`if some_collection:` over `if len(some_collection):`.

**Iterate on iterables directly:**

```python
# better
for key in my_dict:
    ...
for key, value in my_dict.items():
    ...
```

**Use `dict.setdefault`:**

```python
# better
values = {}
for element in iterable:
    values.setdefault(element, []).append(other_value)
```

Document code (docstrings on methods, simple comments for tricky parts).

## Programming in Odoo

- Avoid creating generators and decorators - only use the ones provided by
  the Odoo API.
- Use `filtered`, `mapped`, `sorted`, etc. to ease code reading and
  performance.

### Propagate the context

The context is a frozendict that cannot be modified. Use `with_context` to
call a method with a different context:

```python
records.with_context(new_context).do_stuff() # all the context is replaced
records.with_context(**additionnal_context).do_other_stuff() # additionnal_context values override native context ones
```

> **Warning (official):** Passing parameters in context can have
> dangerous side effects. Since values propagate automatically, unexpected
> behavior may appear - e.g. `create()` with `default_my_field` in context
> will set that default for every model in the call chain that has a
> `my_field`. If a context key should influence one object's behavior only,
> give it a specific name, ideally prefixed by the module name (see mail
> module's `mail_create_nosubscribe`, `mail_notrack`,
> `mail_notify_user_signature`, ...).

### Think extendable

Keep methods small and single-purpose rather than large and complex - split
a method as soon as it has more than one responsibility. Avoid hardcoding
business logic in a way that blocks extension by a submodule:

```python
# do not do this
# modifying the domain or criteria implies overriding whole method
def action(self):
    ...  # long method
    partners = self.env['res.partner'].search(complex_domain)
    emails = partners.filtered(lambda r: arbitrary_criteria).mapped('email')

# better but do not do this either
# modifying the logic forces to duplicate some parts of the code
def action(self):
    ...
    partners = self._get_partners()
    emails = partners._get_emails()

# better
# minimum override
def action(self):
    ...
    partners = self.env['res.partner'].search(self._get_partner_domain())
    emails = partners.filtered(lambda r: r._filter_partners()).mapped('email')
```

The last version is over-extended for the sake of example - readability
still matters and a tradeoff must be made. Name functions, classes, files,
modules, and packages accordingly.

### Never commit the transaction

The Odoo framework provides the transactional context for all RPC calls. A
new database cursor opens at the start of each RPC call and commits when the
call returns, roughly:

```python
def execute(self, db_name, uid, obj, method, *args, **kw):
    db, pool = pooler.get_db_and_pool(db_name)
    # create transaction cursor
    cr = db.cursor()
    try:
        res = pool.execute_cr(cr, uid, obj, method, *args, **kw)
        cr.commit() # all good, we commit
    except Exception:  # try to be more specific
        cr.rollback() # error, rollback everything atomically
        raise
    finally:
        cr.close() # always close cursor opened manually
    return res
```

Manually calling `cr.commit()` risks partial commits and unclean rollbacks:
inconsistent business data (usually data loss), workflow desynchronization,
documents stuck permanently, and tests that pollute the database.

**Rule: never call `cr.commit()` or `cr.rollback()` yourself, unless you
explicitly created your own database cursor** - and that is exceptional. If
you did create your own cursor, handle error cases, rollback properly, and
close the cursor when done.

You do *not* need to call `cr.commit()`:

- in a model's `_auto_init()` - handled by addons initialization or the ORM
  transaction
- in reports - the framework handles `commit()`
- within `models.TransientModel` methods - called like regular model
  methods, inside the same transaction

### Avoid catching exceptions

Catch only specific exception types, and keep the scope of any `try/except`
as small as possible. Uncaught exceptions are logged and handled by the
framework.

```python
# BAD CODE
try:
    do_something()
except Exception as e:
    # if we caught a ValidationError, we did not rollback and we left the
    # ORM in an undefined state
    _logger.warning(e)
```

For scheduled actions (`ir.cron`), rollback changes if you catch an error
and want to continue - scheduled actions run in a separate transaction, so
you can rollback or commit directly to signal progress.

If you must handle framework exceptions, use savepoints to isolate the
function - this flushes computations on entering the block and rolls back
properly on exception:

```python
try:
    with self.env.cr.savepoint():
        do_stuff()
except ...:
    ...
```

> **Warning (official):** After starting more than 64 savepoints in a
> single transaction, PostgreSQL slows down, and savepoints have a large
> overhead when the server runs replicas. If savepointing in a loop (e.g.
> batch-processing records one by one), limit the batch size - beyond that,
> consider a scheduled job instead, or accept the performance penalty.

### Use the translation method correctly

Odoo's `_()` (GetText-like) marks a static string for runtime translation,
available at `self.env._`. It should only be used for static strings
written manually in the code - not for field values (use the `translate`
flag on the field for those).

Calls must always be in the form `self.env._('literal string', ...)`:

```python
_ = self.env._

# good: plain strings
error = _('This record is locked!')

# good: strings with formatting patterns included
error = _('Record %s cannot be modified!', record)

# ok too: multi-line literal strings
error = _("""This is a bad multiline example
             about record %s!""", record)
error = _('Record %s cannot be modified' \
          'after being validated!', record)

# bad: tries to translate after string formatting
#      (pay attention to brackets!)
# This does NOT work and messes up the translations!
error = _('Record %s cannot be modified!' % record)

# bad: formatting outside of translation
# This won't benefit from fallback mechanism in case of bad translation
error = _('Record %s cannot be modified!') % record

# bad: dynamic string, string concatenation, etc are forbidden!
# This does NOT work and messes up the translations!
error = _("'" + que_rec['question'] + "' \n")

# bad: field values are automatically translated by the framework
# This is useless and will not work the way you think:
error = _("Product %s is out of stock!") % _(product.name)
# and the following will of course not work as already explained:
error = _("Product %s is out of stock!" % product.name)

# Instead you can do the following and everything will be translated,
# including the product name if its field definition has the
# translate flag properly set:
error = _("Product %s is not available!", product.name)
```

Translators work with the literal values passed to `_()` - keep them easy to
understand and keep formatting minimal. Formatting patterns (`%s`, `%d`,
newlines, ...) must be preserved, used sensibly:

```python
# Bad: makes the translations hard to work with
error = "'" + question + _("' \nPlease enter an integer value ")

# Ok (pay attention to position of the brackets too!)
error = _("Answer to question %s is not valid.\n" \
          "Please enter an integer value.", question)

# Better
error = _("Answer to question %(title)s is not valid.\n" \
          "Please enter an integer value.", title=question)
```

Prefer `%` over `.format()` when replacing a single variable, and
`%(varname)` over positional `%s` when replacing multiple variables - it
eases translation for the community translators.

## Symbols and Conventions

### Model name (dot notation, prefixed by module name)

- **Model**: singular form (`res.partner`, `sale.order` - not
  `res.partnerS`/`saleS.orderS`)
- **Transient (wizard)**: `<related_base_model>.<action>`, where
  `related_base_model` is the base model related to the transient, and
  `action` is a short description of what it does. Avoid the word "wizard".
  E.g. `account.invoice.make`, `project.task.delegate.batch`
- **Report model** (SQL views): `<related_base_model>.report.<action>`,
  following the transient convention
- **Odoo Python class**: Pascal case

```python
class AccountInvoice(models.Model):
    ...
```

### Variable name

- Pascal case for model variables
- underscore lowercase notation for common variables
- suffix with `_id`/`_ids` when it holds a record id or list of ids - don't
  use `partner_id` to hold a `res.partner` recordset

```python
Partner = self.env['res.partner']
partners = Partner.browse(ids)
partner_id = partners[0].id
```

- One2Many/Many2Many fields: always suffix `_ids` (e.g.
  `sale_order_line_ids`)
- Many2One fields: suffix `_id` (e.g. `partner_id`, `user_id`, ...)

### Method conventions

| Kind | Pattern |
|---|---|
| Compute field | `_compute_<field_name>` |
| Search method | `_search_<field_name>` |
| Default method | `_default_<field_name>` |
| Selection method | `_selection_<field_name>` |
| Onchange method | `_onchange_<field_name>` |
| Constraint method | `_check_<constraint_name>` |
| Action method | `action_<...>` (single record - call `self.ensure_one()` first) |

### Attribute order in a Model

1. Private attributes (`_name`, `_description`, `_inherit`, ...)
2. Default method and `default_get`
3. Field declarations
4. SQL constraints and indexes
5. Compute, inverse and search methods (same order as field declaration)
6. Selection methods (return computed values for selection fields)
7. Constrains methods (`@api.constrains`) and onchange methods
   (`@api.onchange`)
8. CRUD methods (ORM overrides)
9. Action methods
10. Other business methods

```python
class Event(models.Model):
    # Private attributes
    _name = 'event.event'
    _description = 'Event'

    # Default methods
    def _default_name(self):
        ...

    # Fields declaration
    name = fields.Char(string='Name', default=_default_name)
    seats_reserved = fields.Integer(string='Reserved Seats', store=True,
        readonly=True, compute='_compute_seats')
    seats_available = fields.Integer(string='Available Seats', store=True,
        readonly=True, compute='_compute_seats')
    price = fields.Integer(string='Price')
    event_type = fields.Selection(string="Type", selection='_selection_type')

    # compute and search fields, in the same order of fields declaration
    @api.depends('seats_max', 'registration_ids.state', 'registration_ids.nb_register')
    def _compute_seats(self):
        ...

    @api.model
    def _selection_type(self):
        return []

    # Constraints and onchanges
    @api.constrains('seats_max', 'seats_available')
    def _check_seats_limit(self):
        ...

    @api.onchange('date_begin')
    def _onchange_date_begin(self):
        ...

    # CRUD methods (and name_search, _search, ...) overrides
    @api.model
    def create(self, vals_list):
        ...

    # Action methods
    def action_validate(self):
        self.ensure_one()
        ...

    # Business methods
    def mail_user_confirm(self):
        ...
```
