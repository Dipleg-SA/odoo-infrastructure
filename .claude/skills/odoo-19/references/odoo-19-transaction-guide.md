# Odoo 19 Transaction Guide

Guide for handling database transactions in Odoo 19: errors, savepoints, and serialization failures.

## Table of Contents
- [Transaction Overview](#transaction-overview)
- [Database Errors](#database-errors)
- [Savepoints](#savepoints)
- [Error Handling](#error-handling)
- [Serialization Failures](#serialization-failures)
- [Best Practices](#best-practices)

---

## Transaction Overview

Odoo uses database transactions to ensure data consistency.

### Transaction Properties

| Property | Description |
|-----------|-------------|
| **Atomicity** | All or nothing |
| **Consistency** | Data remains valid |
| **Isolation** | Concurrent transactions don't interfere |
| **Durability** | Committed data persists |

### Transaction Flow

```
Begin Transaction
├── Execute Operations
├── (Commit or Rollback)
└── End Transaction
```

---

## Database Errors

### Common Errors

| Error | When |
|-------|------|
| `UniqueViolation` | Duplicate unique constraint |
| `NotNullViolation` | NULL in NOT NULL column |
| `ForeignKeyViolation` | Invalid foreign key |
| `CheckViolation` | CHECK constraint failed |
| `SerializationFailure` | Concurrent modification |

### Catch Database Errors

```python
from odoo.exceptions import ValidationError, UserError
from psycopg2 import errors

try:
    record.write({'field': 'value'})
except errors.UniqueViolation as e:
    raise ValidationError("Duplicate value!")
except errors.NotNullViolation as e:
    raise ValidationError("Required field missing!")
```

---

## Savepoints

Savepoints isolate errors within a transaction.

### Using Savepoints

Use `cr.savepoint()` as a context manager — don't issue raw `SAVEPOINT`/`ROLLBACK TO SAVEPOINT`/`RELEASE SAVEPOINT` SQL yourself. It handles naming (no collisions on recursive/nested calls) and automatically rolls back on any exception, releases on success.

```python
def process_records(self):
    for record in self:
        try:
            with self.env.cr.savepoint():
                record.process()
        except Exception as e:
            _logger.warning("Failed to process %s: %s", record, e)
```

> **Verified against `odoo/sql_db.py:217`**: `Cursor.savepoint(flush=True) -> Savepoint` is the real, idiomatic API — used extensively in real modules (`addons/account/models/chart_template.py:248`, `addons/auth_signup/models/res_users.py:125`, `addons/point_of_sale/models/stock_picking.py`, etc.). A hardcoded raw savepoint name like `"my_savepoint"` collides if the method runs recursively or is entered twice in the same transaction.

---

## Error Handling

### Retry on Serialization Failure

Odoo already retries automatically at the request/RPC/cron dispatch level — you generally don't need to write your own retry logic. `odoo.service.model.retrying()` retries the whole call (up to `MAX_TRIES_ON_CONCURRENCY_FAILURE` = 5 times) on `SerializationFailure`, `LockNotAvailable`, or `DeadlockDetected` by doing a **full transaction rollback and re-running the entire function from the top** — not by rolling back to a savepoint and continuing mid-function, which doesn't work: after a serialization failure the whole transaction's snapshot is invalid, so a savepoint inside it can't be resumed.

```python
# odoo/service/model.py (framework internals, shown for reference — you don't call this directly)
for tryno in range(1, MAX_TRIES_ON_CONCURRENCY_FAILURE + 1):
    try:
        result = func()
        env.cr.flush()
        break
    except (IntegrityError, OperationalError, ConcurrencyError) as exc:
        env.cr.rollback()
        env.transaction.reset()
        # ... retry from the top
```

> **Verified against `odoo/service/model.py:29-216`**: `PG_CONCURRENCY_EXCEPTIONS_TO_RETRY = (errors.LockNotAvailable, errors.SerializationFailure, errors.DeadlockDetected)`, `MAX_TRIES_ON_CONCURRENCY_FAILURE = 5`. If you're writing a custom controller or cron method, you don't need a retry decorator — the framework already wraps the call. A hand-written `SAVEPOINT`-based retry (as this section previously showed) is not mechanically valid for serialization failures.

### Handle Validation Errors

```python
from odoo.exceptions import ValidationError

@api.constrains('email')
def _check_email(self):
    for record in self:
        if not tools.email_normalize(record.email):
            raise ValidationError("Invalid email: %s" % record.email)
```

---

## Serialization Failures

### What is Serialization Failure?

Occurs when two transactions try to modify the same data concurrently.

### Avoid Serialization Failures

```python
# BAD: Loop with search and write
def process(self):
    for record in self.search([('state', '=', 'draft')]):
        record.write({'state': 'done'})

# GOOD: Single write
def process(self):
    self.search([('state', '=', 'draft')]).write({'state': 'done'})
```

### Use SQL FOR UPDATE

```python
self.env.cr.execute("SELECT id FROM my_model WHERE id IN %s FOR UPDATE", (tuple(self.ids),))
# Process records
```

---

## Commit and Rollback

### Auto Commit

Odoo commits automatically **once per transaction** (one HTTP request, one RPC call, one cron run) — not after each individual write. All operations in the same method share one uncommitted transaction until it ends successfully.

```python
# Both writes are part of the SAME transaction — if the second one
# raises, the first is rolled back too, it was never committed on its own.
record1.write({'field': 'value'})
record2.write({'field': 'value'})
# Transaction commits here, once, when the request/call finishes without error
```

> **Verified against `odoo/sql_db.py`**: the commit happens in the cursor's `__exit__` (`with cr: ...`), wrapping the whole call — `self.commit()` runs only if no exception occurred, once for the entire block, not per statement.

### Manual Rollback

```python
try:
    # Multiple operations
    record1.write({'field': 'value'})
    record2.write({'field': 'value'})
except Exception as e:
    # Rollback entire transaction
    self.env.cr.rollback()
    raise
```

---

## Best Practices

### Batch Operations

```python
# GOOD: Batch create
def create_records(self, values_list):
    return self.create(values_list)

# BAD: Create in loop
def create_records(self, values_list):
    for values in values_list:
        self.create(values)
```

### Use Context for Special Cases

```python
# Skip tracking for bulk update
records.with_context(tracking_disable=True).write({'field': 'value'})
```

### Validate Before Writing

```python
@api.constrains('email')
def _check_email(self):
    # Validate before write
    for record in self:
        if not tools.email_normalize(record.email):
            raise ValidationError("Invalid email")
```

---

## Common Patterns

### Safe Update Pattern

```python
def safe_update(self, values):
    try:
        self.write(values)
    except errors.UniqueViolation:
        raise UserError("Duplicate entry!")
    except errors.NotNullViolation:
        raise UserError("Required field missing!")
```

### Bulk Processing with Savepoints

```python
def bulk_process(self, records):
    for record in records:
        try:
            with self.env.cr.savepoint():
                record.process()
        except Exception as e:
            _logger.warning("Failed: %s", e)
```

---

## References

- PostgreSQL documentation on transactions
- Odoo 19 ORM documentation
- Verified against `.repos/odoo` (community, `version_info = (19, 0, 0, FINAL, 0, '')`): `odoo/sql_db.py`, `odoo/service/model.py`, `odoo/tools/mail.py`.
