# Javascript (official, verbatim)

Source: https://www.odoo.com/documentation/19.0/es_419/contributing/development/coding_guidelines.html

Read this file when writing or editing files under a module's `static/`
folder.

## Static files organization

The Odoo server statically serves every file located in a `static/` folder,
prefixed with the addon name - a file at
`addons/web/static/src/js/some_file.js` is served at
`your-odoo-server.com/web/static/src/js/some_file.js`.

Convention:

- `static/` - all static files in general
- `static/lib/` - JS libs, each in its own subfolder (e.g. jquery files live
  in `addons/web/static/lib/jquery`)
- `static/src/` - the generic static source code folder
  - `static/src/css/` - all css files
  - `static/fonts`
  - `static/img`
  - `static/src/js/`
    - `static/src/js/tours/` - end-user tour files (tutorials, not tests)
  - `static/src/scss/` - scss files
  - `static/src/xml/` - all QWeb templates rendered in JS
- `static/tests/` - all test-related files
  - `static/tests/tours/` - tour *test* files (not tutorials)

## Javascript coding guidelines

- `use strict;` is recommended for all JavaScript files
- Use a linter (jshint, ...)
- Never add minified JavaScript libraries
- Use Pascal case for class declaration

More precise JS guidelines are detailed in the github wiki. See also the
Javascript References documentation for existing APIs.
