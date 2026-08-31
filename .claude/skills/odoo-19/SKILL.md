---
name: odoo-19
description: >-
  Odoo 19 development knowledge base with 18 specialized guides plus a
  version-highlights reference covering
  Actions (ir.actions.*, cron jobs, server actions), Controllers (HTTP
  routing, endpoints, auth types), Data files (XML/CSV records, shortcuts,
  noupdate), API Decorators (@api.depends, @api.constrains, @api.ondelete,
  @api.onchange, @api.model, @api.private), SQL Constraints (models.Constraint
  replacing _sql_constraints), Database Indexes (models.Index), Module
  development (manifest, wizards, reports), Field types (Char, Text, Monetary,
  relational fields), Manifest configuration (__manifest__.py, dependencies,
  asset bundles), Mixins (mail.thread, mail.activity.mixin, mail.alias.mixin,
  utm.mixin), ORM Model methods (search, CRUD, domain filters, recordsets,
  CamelCase model naming), Migration scripts (pre/post/end hooks, data
  migration), OWL frontend components (hooks, services, lifecycle),
  Performance optimization (N+1 prevention, batch ops, _read_group), QWeb
  Reports (PDF/HTML, paper formats, barcodes, t-out), Security/ACL (record
  rules, field permissions, privilege-based groups, @api.private), Testing
  (TransactionCase, HttpCase, mocking, query count assertions), Transactions
  (savepoints, UniqueViolation, serialization failures), Translations (i18n,
  PO files, translatable fields), XML Views (list/form/search, kanban card
  templates, xpath inheritance, QWeb templates). Use when writing, reviewing,
  or debugging any Odoo 19 Python or XML code, creating or modifying modules,
  fixing performance issues, or looking up Odoo 19 API patterns and best
  practices — e.g. "how do I add a compute field in Odoo 19", "why isn't my
  SQL constraint working", "why does uninstalling my module fail".
---

# Odoo 19 Skill - Master Index

Master index for all Odoo 19 development guides. Read the appropriate guide from `references/` based on your task.

## Quick Reference

| Topic          | File                                      | When to Use                                             |
| -------------- | ----------------------------------------- | ------------------------------------------------------- |
| API Highlights | `references/odoo-19-api.md`               | Quick check of what changed vs older Odoo versions      |
| Actions        | `references/odoo-19-actions-guide.md`     | Creating actions, menus, scheduled jobs, server actions |
| API Decorators | `references/odoo-19-decorator-guide.md`   | Using @api decorators, compute fields, validation       |
| Controllers    | `references/odoo-19-controller-guide.md`  | Writing HTTP endpoints, routes, web controllers         |
| Data Files     | `references/odoo-19-data-guide.md`        | XML/CSV data files, records, shortcuts                  |
| Development    | `references/odoo-19-development-guide.md` | Scaffolding a first module end-to-end (overview only — see the dedicated guide below for depth on any one topic) |
| Field Types    | `references/odoo-19-field-guide.md`       | Defining model fields, choosing field types             |
| Manifest       | `references/odoo-19-manifest-guide.md`    | **manifest**.py configuration, dependencies, hooks      |
| Migration      | `references/odoo-19-migration-guide.md`   | Upgrading modules, data migration, version changes      |
| Mixins         | `references/odoo-19-mixins-guide.md`      | mail.thread, activities, email aliases, tracking        |
| Model Methods  | `references/odoo-19-model-guide.md`       | Writing ORM queries, CRUD operations, domain filters    |
| OWL Components | `references/odoo-19-owl-guide.md`         | Building OWL UI components, hooks, services             |
| Performance    | `references/odoo-19-performance-guide.md` | Optimizing queries, fixing slow code, preventing N+1    |
| Reports        | `references/odoo-19-reports-guide.md`     | QWeb reports, PDF/HTML, templates, paper formats        |
| Security       | `references/odoo-19-security-guide.md`    | Access rights, record rules, field permissions          |
| Testing        | `references/odoo-19-testing-guide.md`     | Writing tests, mocking, assertions, browser testing     |
| Transactions   | `references/odoo-19-transaction-guide.md` | Handling database errors, savepoints, UniqueViolation   |
| Translation    | `references/odoo-19-translation-guide.md` | Adding translations, localization, i18n                 |
| Views & XML    | `references/odoo-19-view-guide.md`        | Writing XML views, actions, menus, QWeb templates       |

## File Structure

```
skills/odoo-19/
├── SKILL.md                          # This file - master index
└── references/                       # Development guides + version highlights
    ├── odoo-19-api.md
    ├── odoo-19-actions-guide.md
    ├── odoo-19-controller-guide.md
    ├── odoo-19-data-guide.md
    ├── odoo-19-decorator-guide.md
    ├── odoo-19-development-guide.md
    ├── odoo-19-field-guide.md
    ├── odoo-19-manifest-guide.md
    ├── odoo-19-migration-guide.md
    ├── odoo-19-mixins-guide.md
    ├── odoo-19-model-guide.md
    ├── odoo-19-owl-guide.md
    ├── odoo-19-performance-guide.md
    ├── odoo-19-reports-guide.md
    ├── odoo-19-security-guide.md
    ├── odoo-19-testing-guide.md
    ├── odoo-19-transaction-guide.md
    ├── odoo-19-translation-guide.md
    └── odoo-19-view-guide.md
```

## Key Changes & Anti-Patterns

For the condensed old-vs-new cheat sheet, the review checklist, and the `@api` decorator decision tree, see **`references/odoo-19-api.md`** (Key Changes At a Glance, Quick Review Checklist) and **`references/odoo-19-decorator-guide.md`** (Decorator Decision Tree) — kept there as the single source of truth instead of duplicated here.

## Base Code Reference (Odoo 19)

All guides are based on analysis of Odoo 19 source code:

- `odoo/orm/models.py` - ORM implementation (moved from `odoo/models.py` in 19 — `odoo/models.py` no longer exists as a file; `odoo/models/__init__.py` re-exports from here for backward-compatible imports)
- `odoo/orm/fields.py` - Field types (moved from `odoo/fields.py`, same re-export pattern via `odoo/fields/__init__.py`)
- `odoo/orm/decorators.py` - Decorators (moved from `odoo/api.py`, same re-export pattern via `odoo/api/__init__.py`)
- `odoo/http.py` - HTTP layer
- `odoo/exceptions.py` - Exception types
- `odoo/tools/translate.py` - Translation system
- `odoo/addons/base/models/res_lang.py` - Language model
- `addons/web/static/src/core/l10n/translation.js` - JS translations

## External Documentation

- [Odoo 19 Official Documentation](https://github.com/odoo/documentation/tree/19.0)
- [Odoo 19 Developer Reference](https://github.com/odoo/documentation/blob/19.0/developer/reference/orm.rst)
