# Odoo 19 OWL Guide

Guide for building OWL (Owl Web Library) components in Odoo 19.

## Table of Contents

- [OWL Overview](#owl-overview)
- [Component Structure](#component-structure)
- [Hooks](#hooks)
- [Services](#services)
- [State Management](#state-management)
- [QWeb Templates](#qweb-templates)
- [Translations](#translations)

---

## OWL Overview

OWL is a JavaScript framework for building web UI components in Odoo.

### Key Concepts

| Concept       | Description                |
| ------------- | -------------------------- |
| **Component** | Reusable UI building block |
| **State**     | Reactive data              |
| **Props**     | Component properties       |
| **Hooks**     | Lifecycle functions        |
| **Template**  | QWeb template              |

---

## Component Structure

### Basic Component

```javascript
import { Component } from "@odoo/owl";

export class MyComponent extends Component {
  static template = "my_module.MyComponent";
  static props = {
    value: { type: String, optional: true },
  };

  setup() {
    // Component setup
  }
}
```

### Register Component

```javascript
import { registry } from "@web/core/registry";

registry.category("actions").add("my_component", MyComponent);
```

### Use in View

```xml
<widget name="my_component" options="{'value': 'Hello'}"/>
```

---

## Hooks

### Setup Hook

Called when component is created:

```javascript
setup() {
    // Initialize state
    this.state = useState({ count: 0 });

    // Call services
    this.rpc = useService("rpc");
    this.orm = useService("orm");
    this.action = useService("action");
}
```

### Lifecycle Hooks

| Hook              | When                  |
| ----------------- | --------------------- |
| `setup()`         | Component creation    |
| `onWillStart()`   | Before render (async) |
| `onMounted()`     | After render          |
| `onWillUnmount()` | Before destroy        |
| `onWillPatch()`   | Before update         |
| `onPatched()`     | After update          |

### Example

```javascript
setup() {
    onWillStart(this.onWillStart);
    onMounted(this.onMounted);
    onWillUnmount(this.onWillUnmount);
}

async onWillStart() {
    // Load data before render
}

onMounted() {
    // After render
}

onWillUnmount() {
    // Cleanup
}
```

---

## Services

### Common Services

| Service        | Description         |
| -------------- | ------------------- |
| `orm`          | Database operations |
| `rpc`          | RPC calls           |
| `action`       | Execute actions     |
| `dialog`       | Show dialogs        |
| `notification` | Show notifications  |
| `router`       | Navigation          |
| `user`         | Current user        |
| `company`      | Current company     |

### Use Service

```javascript
setup() {
    this.orm = useService("orm");
    this.rpc = useService("rpc");
    this.action = useService("action");
    this.dialog = useService("dialog");
    this.notification = useService("notification");
}
```

### ORM Service

```javascript
// Search — returns IDs only (number[]), not record data
const ids = await this.orm.search("my.model", [["active", "=", true]]);

// Search + read in one call — use this when you need record data
const records = await this.orm.searchRead("my.model", [["active", "=", true]], ["name", "value"]);

// Read
const data = await this.orm.read("my.model", ids, ["name", "value"]);

// Create — takes a list of dicts, returns a list of ids (batch, even for one record)
const [id] = await this.orm.create("my.model", [{ name: "Test" }]);

// Write
await this.orm.write("my.model", [id], { name: "Updated" });

// Unlink
await this.orm.unlink("my.model", [id]);
```

> **Verified against `addons/web/static/src/core/orm_service.js`**: `search()` (line 233) only calls the backend `search` method, which returns IDs — for full record data use `searchRead()` (line 244). `create()` (line 149) runs `validateArray("records", records)` — passing a single dict instead of a list fails validation; it also always returns a list of ids, never a single id.

### RPC Service

```javascript
// Call controller
const result = await this.rpc("/my/controller", { param: "value" });
```

### Action Service

```javascript
// Do action
await this.action.doAction({
  type: "ir.actions.act_window",
  res_model: "my.model",
  views: [
    [false, "list"],
    [false, "form"],
  ],
});
```

### Dialog Service

```javascript
// Add dialog
this.dialog.add(MyDialog, {
    title: "My Dialog",
    confirm: () => {...},
});
```

### Notification Service

```javascript
// Show notification
this.notification.notify({
  message: "Success!",
  type: "success",
});
```

---

## State Management

### useState

```javascript
setup() {
    this.state = useState({
        count: 0,
        name: "",
    });
}

increment() {
    this.state.count++;
}
```

### useState in Template

```xml
<div t-out="state.count"/>
<button t-on-click="increment">+</button>
```

### Computed State

OWL has no `computed()` primitive — `computed` isn't defined anywhere in `@odoo/owl` and calling it raises `ReferenceError`. Use a plain JS getter instead:

```javascript
setup() {
    this.state = useState({count: 0});
}

get double() {
    return this.state.count * 2;
}
```

> **Verified against `addons/web/static/lib/owl/owl.js`**: `grep -n "computed"` returns 0 matches — no such export exists.

---

## QWeb Templates

### Basic Template

```xml
<?xml version="1.0" encoding="UTF-8"?>
<templates xml:space="preserve">
    <t t-name="my_module.MyComponent" owl="1">
        <div class="my_component">
            <h1 t-out="props.title"/>
            <p t-out="state.message"/>
        </div>
    </t>
</templates>
```

### Event Handlers

```xml
<button t-on-click="increment">Increment</button>
<input t-on-change="onChange"/>
```

### Loops and Conditions

```xml
<!-- Loop -->
<div t-foreach="state.records" t-as="record" t-key="record.id">
    <span t-out="record.name"/>
</div>

<!-- Condition -->
<div t-if="state.show">Visible when true</div>
<div t-else="">Visible when false</div>
```

---

## Translations

### Translate in JavaScript

```javascript
import { _t } from "@web/core/l10n/translation";

this.message = _t("Hello World");
```

### Translate with Parameters

```javascript
this.message = _t("Hello %(name)s", { name: "John" });
```

### Translate in Template

There is no `translate()` function callable inside a QWeb expression — `translate` in `owl.js` is an internal template-compiler flag, not something exposed to template expressions. Static text nodes are translated automatically at compile time; for dynamic strings, translate in JavaScript with `_t()` and expose the result to the template:

```javascript
setup() {
    this.greeting = _t("Hello World");
}
```

```xml
<span t-out="greeting"/>
```

> **Verified against `addons/web/static/lib/owl/owl.js`**: `translate` only appears as an internal compiler context flag (`ctx.translate`), never as a callable exposed to template expressions.

---

## Examples

### Counter Component

```javascript
import { Component, useState } from "@odoo/owl";
import { _t } from "@web/core/l10n/translation";

export class Counter extends Component {
  static template = "my_module.Counter";

  setup() {
    this.state = useState({ count: 0 });
  }

  increment() {
    this.state.count++;
  }

  decrement() {
    this.state.count--;
  }
}
```

```xml
<templates xml:space="preserve">
    <t t-name="my_module.Counter" owl="1">
        <div class="counter">
            <button class="btn btn-secondary" t-on-click="decrement">-</button>
            <span t-out="state.count"/>
            <button class="btn btn-secondary" t-on-click="increment">+</button>
        </div>
    </t>
</templates>
```

### Data Loading Component

```javascript
import { Component, useState, onWillStart } from "@odoo/owl";
import { useService } from "@web/core/utils/hooks";

export class DataComponent extends Component {
  static template = "my_module.DataComponent";

  setup() {
    this.orm = useService("orm");
    this.state = useState({
      records: [],
      loading: true,
    });

    onWillStart(this.loadData);
  }

  async loadData() {
    this.state.records = await this.orm.search("my.model", [], {
      limit: 10,
    });
    this.state.loading = false;
  }
}
```

---

## Best Practices

### Use Hooks for Side Effects

```javascript
setup() {
    onMounted(() => {
        // Side effects here
    });
}
```

### Cleanup Resources

```javascript
setup() {
    onWillUnmount(() => {
        // Cleanup here
    });
}
```

### Avoid Direct DOM Manipulation

Use templates and reactive state instead.

### Split Components

Keep components small and focused.

```javascript
// Good: Small focused component
export class UserName extends Component {
  static template = "my_module.UserName";
}

// Bad: Large monolithic component
export class Everything extends Component {
  static template = "my_module.Everything";
}
```

---

## References

- OWL documentation
- Odoo 19 Web framework docs
- Verified against `.repos/odoo` (community, `version_info = (19, 0, 0, FINAL, 0, '')`): `addons/web/static/lib/owl/owl.js`, `addons/web/static/src/core/orm_service.js`, `addons/web/static/src/core/l10n/translation.js`, `addons/web/static/src/core/utils/hooks.js`, `addons/web/static/src/core/utils/strings.js`.
