# CSS and SCSS (official, verbatim)

Source: https://www.odoo.com/documentation/19.0/es_419/contributing/development/coding_guidelines.html

Read this file when writing or editing `.scss`/`.css` files under a
module's `static/src/scss/` (or `static/src/css/`).

## Syntax and Formatting

```scss
.o_foo, .o_foo_bar, .o_baz {
   height: $o-statusbar-height;

   .o_qux {
      height: $o-statusbar-height * 0.5;
   }
}

.o_corge {
   background: $o-list-footer-bg-color;
}
```

- four (4) space indents, no tabs
- columns of max. 80 characters wide
- opening brace (`{`): empty space after the last selector
- closing brace (`}`): on its own new line
- one line for each declaration
- meaningful use of whitespace

## Properties order

Order properties from the "outside" in, starting from position and ending
with decorative rules (font, filter, etc.). Scoped SCSS variables and CSS
variables go at the very top, followed by an empty line separating them from
other declarations.

```scss
.o_element {
   $-inner-gap: $border-width + $legend-margin-bottom;

   --element-margin: 1rem;
   --element-size: 3rem;

   @include o-position-absolute(1rem);
   display: block;
   margin: var(--element-margin);
   width: calc(var(--element-size) + #{$-inner-gap});
   border: 0;
   padding: 1rem;
   background: blue;
   font-size: 1rem;
   filter: blur(2px);
}
```

## Naming Conventions

Avoid id selectors. Prefix classes with `o_<module_name>` (the module's
technical name, e.g. `sale`, `im_chat`, or the module's main route for
website modules, e.g. `o_forum` for `website_forum`). The webclient is the
only exception - it just uses the `o_` prefix.

Avoid hyper-specific classes and variable names. When naming nested
elements, opt for the "Grandchild" approach instead of chaining full
ancestry into the class name:

```html
<!-- Don't -->
<div class="o_element_wrapper">
   <div class="o_element_wrapper_entries">
      <span class="o_element_wrapper_entries_entry">
         <a class="o_element_wrapper_entries_entry_link">Entry</a>
      </span>
   </div>
</div>

<!-- Do -->
<div class="o_element_wrapper">
   <div class="o_element_entries">
      <span class="o_element_entry">
         <a class="o_element_link">Entry</a>
      </span>
   </div>
</div>
```

Besides being more compact, this eases maintenance since it limits renames
when the DOM changes.

## SCSS Variables

Convention: `$o-[root]-[element]-[property]-[modifier]`

- `$o-` - the prefix
- `[root]` - the component or module name (components take priority)
- `[element]` - optional identifier for inner elements
- `[property]` - the property/behavior the variable defines
- `[modifier]` - optional modifier

```scss
$o-block-color: value;
$o-block-title-color: value;
$o-block-title-color-hover: value;
```

## SCSS Variables (scoped)

Declared within blocks, not accessible from the outside. Convention:
`$-[variable name]`.

```scss
.o_element {
   $-inner-gap: compute-something;

   margin-right: $-inner-gap;

   .o_element_child {
      margin-right: $-inner-gap * 0.5;
   }
}
```

## SCSS Mixins and Functions

Convention: `o-[name]`, with descriptive names. For functions, use
imperative verbs (get, make, apply, ...). Optional arguments use the scoped
variable form, `$-[argument]`.

```scss
@mixin o-avatar($-size: 1.5em, $-radius: 100%) {
   width: $-size;
   height: $-size;
   border-radius: $-radius;
}

@function o-invert-color($-color, $-amount: 100%) {
   $-inverse: change-color($-color, $-hue: hue($-color) + 180);

   @return mix($-inverse, $-color, $-amount);
}
```

## CSS Variables

Use strictly for DOM-related, contextual adaptation of design and layout.
Convention (BEM-based): `--[root]__[element]-[property]--[modifier]`

- `[root]` - the component or module name (components take priority)
- `[element]` - optional identifier for inner elements
- `[property]` - the property/behavior the variable defines
- `[modifier]` - optional modifier

```scss
.o_kanban_record {
   --KanbanRecord-width: value;
   --KanbanRecord__picture-border: value;
   --KanbanRecord__picture-border--active: value;
}

// Adapt the component when rendered in another context.
.o_form_view {
   --KanbanRecord-width: another-value;
   --KanbanRecord__picture-border: another-value;
   --KanbanRecord__picture-border--active: another-value;
}
```

### Use of CSS Variables

CSS variables are strictly DOM-related - used to contextually adapt design
and layout rather than manage the global design-system. Define them inside
the component's main block, with a default fallback:

```scss
/* my_component.scss */
.o_MyComponent {
   color: var(--MyComponent-color, #313131);
}

/* my_dashboard.scss */
.o_MyDashboard {
   /* Adapt the component in this context only */
   --MyComponent-color: #017e84;
}
```

### CSS and SCSS Variables

SCSS variables are imperative and compiled away; CSS variables are
declarative and included in the final output. In Odoo, use SCSS variables to
define the design-system, and CSS variables for contextual adaptations:

```scss
/* secondary_variables.scss */
$o-component-color: $o-main-text-color;
$o-dashboard-color: $o-info;

/* component.scss */
.o_component {
   color: var(--MyComponent-color, #{$o-component-color});
}

/* dashboard.scss */
.o_dashboard {
   --MyComponent-color: #{$o-dashboard-color};
}
```

### The `:root` pseudo-class

Defining CSS variables on `:root` to access/modify them globally is a
technique **not normally used** in Odoo's UI - use SCSS for that instead.
Exceptions should be fairly apparent, such as templates shared across
bundles that need a certain level of contextual awareness to render
properly.
