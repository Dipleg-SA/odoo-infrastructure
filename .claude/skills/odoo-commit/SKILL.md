---
name: odoo-commit
description: >
  Guides Odoo-style commit creation following official Odoo git guidelines:
  drafts `[TAG] module: short description` messages, decides whether to
  amend or create a new commit, stages files explicitly, commits via
  `git commit -F`, and keeps history clean before PRs. This skill should be
  used whenever the user asks to commit, write a commit message, amend,
  squash, or clean up history in a repository that looks like Odoo (an
  `__manifest__.py`/addons layout, or `[FIX]`/`[IMP]`-style tags already in
  `git log`) - even for a bare "commit this" or "clean up my commits before
  the PR". Takes priority over generic commit skills once the repo is
  recognized as Odoo-style.
---

## Workflow

1. Run `git diff --stat` and `git status --short` to see what changed, plus
   `git log -1 --oneline` to see the last local commit.
2. Decide whether to amend the last unpushed commit or draft a new message -
   read `references/git-mechanics.md` for the exact detection commands and
   the `--amend` flow.
3. Stage relevant files by name - never `git add -A` or `git add .`.
4. Pick the tag (see the table below; read `references/tag-disambiguation.md`
   if two tags both seem to fit) and draft the message per the Format section
   below. For the exact official wording of a rule, or one of the official
   example commits, read `references/git-guidelines-official.md`.
5. Commit with `git commit -F <file>` - see `references/git-mechanics.md`
   for the temp-file flow.
6. Before opening a pull request, squash back-and-forth commits into one
   clean commit per logical change - see `references/git-mechanics.md` for
   the amend/rebase mechanics and the OCA squash guideline.
7. Report the resulting commit hash and subject.

Do not bypass pre-commit hooks. If a hook fails, fix the issue, re-stage the
changes, and create the commit again.

## Format

```
[TAG] module: short description

Optional body explaining WHY, not what. What is visible in the diff.
Focus on motivation, constraints, and decisions made.

task-XXXX, opw-XXXXXX
```

## Subject Line Rules

- `[TAG] module: description` - tag in brackets, then module name, colon, space, description
- Target the **whole header** (`[TAG] module: description`) at about 50 characters for
  readability; 72 is a hard ceiling, not something to aim for
- Self-test: the header must read as a valid sentence after "if applied, this commit
  will `<header>`" - e.g. `[IMP] base: prevent to archive users linked to
  active partners` -> *"if applied, this commit will prevent to archive users
  linked to active partners"*
- Never use single, vague words like "bugfix" or "improvements" as the description -
  it must be self-explanatory and state the reason for the change
- Imperative mood: "add", "fix", "remove" - not "added", "fixes"
- No trailing period
- Module = technical module name (e.g. `base`, `account`, `website`, `sale`)
- Avoid touching multiple modules in one commit - split per module so each can be
  reverted independently. If truly unavoidable, list the modules or use `various`

## Tags

| Tag | Use for |
|---|---|
| `[FIX]` | bug fix; used in stable versions, also valid for recent dev bugs |
| `[REF]` | refactoring: feature heavily rewritten |
| `[ADD]` | adding new modules |
| `[REM]` | removing resources: dead code, views, modules |
| `[REV]` | reverting commits |
| `[MOV]` | moving files (no content change; use git mv) |
| `[REL]` | release commits: major/minor stable versions |
| `[IMP]` | improvements: most incremental dev changes |
| `[MERGE]` | merge commits / forward port of bug fixes |
| `[CLA]` | signing Odoo Individual Contributor License |
| `[I18N]` | translation file changes |
| `[PERF]` | performance patches |
| `[CLN]` | code cleanup |
| `[LINT]` | linting passes |

`[REF]` vs `[IMP]` vs `[CLN]`, `[ADD]` vs `[IMP]`, and `[MOV]` vs a plain
content change are the tags people mix up most - read
`references/tag-disambiguation.md` when unsure.

## Body Rules

- Skip body when subject is self-explanatory
- Include body for: non-obvious WHY, breaking changes, migration notes, task references
- **Explain WHY, not WHAT** - the diff already shows what changed. WHAT is only worth
  spelling out when a technical choice or trade-off was involved, and then explain
  WHY that choice was made
- Don't force brevity for its own sake: official Odoo guidance explicitly says not to
  hesitate being verbose when the reasoning deserves it. Every line should still earn
  its place - no restating the diff, no filler
- Wrap at 72 characters per line
- Reference task IDs at the end: `task-XXXX`, `opw-XXXXXX`, `Fixes #123`, `Closes #123`

## What Never Goes In

- "This commit does X" - the diff says what
- "I", "we", "now", "currently"
- AI attribution
- Restating the file name or module when the subject already says it

## Additional Resources

- **`references/git-guidelines-official.md`** - the full official Odoo git
  guidelines text: complete commit-structure rules, all tag descriptions, and
  the official example commits. Read it when drafting the message itself and
  needing the precise official wording, or another example.
- **`references/tag-disambiguation.md`** - practical guidance for the tag
  choices that aren't obvious from a one-line definition (`[REF]` vs `[IMP]`
  vs `[CLN]`, `[ADD]` vs `[IMP]`, `[MOV]` vs a real content change, `[FIX]`
  vs `[PERF]`, when `[REV]` actually applies).
- **`references/git-mechanics.md`** - the git commands behind the workflow:
  detecting whether to amend, the staging/commit-with-`-F` flow, squashing
  and interactive rebase before a PR, and the pre-commit hook rule.
