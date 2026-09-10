# Tag Disambiguation

The official Odoo guidelines define each tag in one line - fine when the
change is obvious, but real diffs often sit between two tags. Read this file
when unsure which tag to pick. This content is not in the official doc; it's
derived from how the tag definitions actually get applied in practice.

## `[REF]` vs `[IMP]` vs `[CLN]`

Ask: **does external behavior change, and how much of the file was rewritten?**

- Behavior changes, even a small addition (new field, new button, new
  condition) → `[IMP]`. This is the default for almost all incremental dev
  work - when in doubt between IMP and something else, IMP is usually right.
- Behavior stays the same, but the implementation was heavily restructured
  (a model split into several, a function's internal approach replaced,
  a large chunk rewritten to use a different pattern) → `[REF]`.
- Behavior stays the same and the change is cosmetic/structural noise
  reduction only (renaming a variable, removing dead code, reformatting,
  removing an unused import) with no restructuring → `[CLN]`.

Rule of thumb: `[REF]` = "I rewrote how this works but it still does the same
thing." `[CLN]` = "I tidied this up, nothing changed." `[IMP]` = "I made it do
something more/different."

## `[ADD]` vs `[IMP]` for new files

`[ADD]` is reserved for adding a **new module** (a new addon directory with
its own `__manifest__.py`). A new field, new view, new wizard, or even an
entirely new file added *inside* an already-existing module is still
`[IMP]` - it's an incremental improvement to that module, not the creation of
a new one.

## `[MOV]` vs `[REM]` + new commit

`[MOV]` means a pure move with `git mv` and **zero content changes** - Git
must still be able to follow the file's history through the rename. If the
move also changes the code (adapting it to a new location, renaming symbols,
fixing imports), it is no longer a pure move:

- Split it into two commits: one `[MOV]` that only moves the file unchanged,
  then a separate `[IMP]`/`[REF]`/`[FIX]` commit with the actual content
  change.
- If splitting isn't practical, don't force `[MOV]` - use the tag that
  matches what actually changed and mention the move in the body.

## `[FIX]` vs `[PERF]`

If the old behavior produced a **wrong result** (crash, incorrect value,
broken flow), it's `[FIX]`, even if the fix happens to also make it faster.
`[PERF]` is only for changes where the old behavior was already correct and
the change is purely about speed/memory (e.g., adding an index, avoiding an
N+1 query, caching a computed value).

## `[REV]`

Use `[REV]` only for reverting a commit that already landed (via
`git revert`), typically because it broke something or is no longer wanted.
For undoing a change that's still local and unpushed, don't create a revert
commit - use `git commit --amend` or interactive rebase to drop it entirely
(see `git-mechanics.md`).

## Cross-module changes

The official rule is to avoid touching multiple modules in one commit. If it
is genuinely unavoidable (e.g., renaming a field referenced across modules),
either list all affected modules (`module_a, module_b: ...`) or use
`various` when more than a handful are touched - but always prefer splitting
into one commit per module when the changes in each module are independently
revertable.
