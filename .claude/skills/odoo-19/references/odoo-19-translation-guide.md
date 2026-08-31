# Odoo 19 Translation Guide

Guide for adding translations and localization in Odoo 19: Python, JavaScript, and QWeb templates.

## Table of Contents

- [Translation Overview](#translation-overview)
- [Python Translations](#python-translations)
- [JavaScript Translations](#javascript-translations)
- [QWeb Translations](#qweb-translations)
- [Translated Fields](#translated-fields)
- [Export/Import](#exportimport)
- [Languages](#languages)

---

## Translation Overview

Odoo supports multi-language through:

- Python `_()` function
- JavaScript `_t()` function
- Translatable fields
- QWeb translation mechanisms

### Supported File Formats

| Format | Use                           |
| ------ | ----------------------------- |
| `.po`  | Portable Object (main format) |
| `.pot` | Portable Object Template      |
| `.csv` | For some data imports         |

---

## Python Translations

### Basic Translation

```python
from odoo import _

def my_method(self):
    message = _("Hello World")
    return message
```

### Translation with Parameters

```python
# Recommended: pass substitutions directly to _()
message = _("Hello %s", name)
message = _("Hello %(name)s", name=name)

# Also works (applying % after the call), but skips the built-in
# handling for Markup/lazy values that _() does when given args/kwargs directly
message = _("Hello %s") % name
```

> **Verified against `odoo/tools/translate.py:578-582`**: `get_text_alias(source, /, *args, **kwargs)` accepts substitutions directly as positional or keyword arguments (not both at once) and passes them to the formatting step — that's the real, current calling convention, not applying `%` externally afterward.

### Lazy Translation

```python
from odoo import _

# Lazy translation (evaluated when displayed, not when imported)
ERROR_MESSAGE = _("Error occurred")

def my_method(self):
    # ERROR_MESSAGE is translated when needed
    return {'error': ERROR_MESSAGE}
```

### Multi-Line Translation

```python
message = _(
    "This is a long message "
    "that spans multiple lines"
)
```

### Context Translation

There is no `default_code` (or similar) parameter for giving translators disambiguation context — `_()` only accepts `*args`/`**kwargs` as substitution values for the string, not a separate context hint:

```python
message = _("Cancel")
```

> **Verified against `odoo/tools/translate.py:578-582`**: any kwarg passed to `_()` is treated as a `%(key)s` substitution value, not translator context. `_("Cancel", default_code="refund_cancel")` would only do something if `"Cancel"` contained a `%(default_code)s` placeholder — it doesn't, so this pattern achieves nothing.

---

## JavaScript Translations

### Basic Translation

```javascript
import { _t } from "@web/core/l10n/translation";

const message = _t("Hello World");
```

### Translation with Parameters

```javascript
const message = _t("Hello %(name)s", { name: "John" });
```

> **Verified against `addons/web/static/src/core/l10n/translation.js`**: it only exports `_t`, `appTranslateFn`, `loadLanguages`, `TranslatedString`, `translationLoaded`, `translatedTerms`, `translatedTermsGlobal`, `translationIsReady` — there is no `lazyTranslation` and no `_lt` export anywhere in the codebase. Both were removed (or never existed in this form) — call `_t()` directly where the translated value is needed.

---

## QWeb Translations

### Translate Static Text

```xml
<template id="my_template">
    <h1>Hello World</h1>
</template>
```

### Translate in Code

There is no `translate()` function callable inside a QWeb expression — it's only an internal template-compiler flag, not exposed to expressions. For dynamic strings, translate in JavaScript/Python and pass the already-translated value to the template:

```javascript
this.greeting = _t("Hello World");
```

```xml
<h1 t-out="greeting"/>
```

> Static text nodes (like `<h1>Hello World</h1>`) are translated automatically at compile time — see "Translate Static Text" above.

### Translate Field Content

```xml
<template id="my_template">
    <span t-field="record.name"/>
</template>
```

### Translate Template Content

```xml
<template id="my_template">
    <div>
        <p>This content is translatable</p>
    </div>
</template>
```

---

## Translated Fields

### Define Translated Field

```python
name = fields.Char(translate=True)
description = fields.Text(translate=True)
```

### Translation Options

```python
# Enable translation
name = fields.Char(translate=True)
```

> **Verified**: `translation_modifiable` is not a real field parameter — `grep -rn "translation_modifiable"` across the whole codebase returns 0 matches. `translate=True` is the only parameter needed to make a field translatable.

### Read Translated Field

```python
# Record is fetched in user's language
record = self.env['my.model'].browse(record_id)
print(record.name)  # Translated name
```

### Read in Specific Language

```python
# Read in French
record_fr = record.with_context(lang='fr_FR')
print(record_fr.name)  # French name
```

---

## Export/Import

### Export Translations

**Via CLI**:

```bash
odoo-bin -d mydb -l fr --i18n-export=fr --stop-after-init
```

**Via UI**:

1. Settings → Translations → Export Translations
2. Select language
3. Choose file format (PO)
4. Export

### Import Translations

**Via CLI**:

```bash
odoo-bin -d mydb -l fr --i18n-import=/path/to/fr.po --stop-after-init
```

**Via UI**:

1. Settings → Translations → Import Translations
2. Select language
3. Upload PO file
4. Import

### Update Translations

**Via CLI**:

```bash
odoo-bin -d mydb -l fr --i18n-overwrite --stop-after-init
```

---

## Languages

### Install Language

```python
# Load language
self.env['res.lang']._activate_lang('fr_FR')
```

> **Verified against `odoo/addons/base/models/res_lang.py:161`**: the real method is `_activate_lang(self, code)`, called on the `env`-bound recordset — `load_lang(cr, uid, code)` doesn't exist; that raw `cr`/`uid` calling style predates the current environment-based API.

### Available Languages

```python
languages = self.env['res.lang'].search([])
for lang in languages:
    print(lang.code, lang.name)
```

### Get User Language

```python
user_lang = self.env.user.lang
context_lang = self.env.context.get('lang', 'en_US')
```

---

## Translation Best Practices

### Always Use Translation Functions

```python
# GOOD
message = _("Hello World")

# BAD
message = "Hello World"
```

### Use Parameters for Dynamic Content

```python
# GOOD
message = _("Hello %(name)s", name=name)

# BAD
message = _("Hello ") + name
```

### Disambiguate Ambiguous Terms in the Source String

There's no per-call context parameter on `_()` — if a short term like "Cancel" is ambiguous for translators, make the source string itself more specific instead:

```python
# GOOD (unambiguous on its own)
message = _("Cancel refund")

# BAD (ambiguous — could be "cancel" as verb, adjective, etc. depending on language)
message = _("Cancel")
```

### Don't Concatenate Translations

```python
# BAD
message = _("Hello ") + name + _("!")

# GOOD
message = _("Hello %(name)s!", name=name)
```

---

## Common Translation Terms

| English | French      | German     | Spanish  |
| ------- | ----------- | ---------- | -------- |
| Save    | Enregistrer | Speichern  | Guardar  |
| Cancel  | Annuler     | Abbrechen  | Cancelar |
| Delete  | Supprimer   | Löschen    | Eliminar |
| Edit    | Modifier    | Bearbeiten | Editar   |
| Create  | Créer       | Erstellen  | Crear    |
| Search  | Rechercher  | Suchen     | Buscar   |

---

## References

- Odoo 19 translation documentation
- GNU gettext documentation
- Verified against `.repos/odoo` (community, `version_info = (19, 0, 0, FINAL, 0, '')`): `odoo/tools/translate.py`, `addons/web/static/src/core/l10n/translation.js`, `odoo/addons/base/models/res_lang.py`.
