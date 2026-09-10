# Git Mechanics

The official Odoo guidelines only cover the *message*, not the git commands
around it. Read this file for the amend/squash/rebase/hooks mechanics behind
steps 2 and 5 of the workflow in `SKILL.md`.

## Detecting whether to amend

Check for a remote-tracking branch first, since the second command errors
without an upstream:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
git log @{u}.. --oneline   # only if the above succeeded
```

If the last local commit (`git log -1 --oneline`) is unpushed and the new
change is a direct continuation or fix of it, fold it in instead of creating
a second commit for the same logical change:

```bash
git add <file>
git commit --amend --no-edit   # or drop --no-edit to also revise the message
```

## Staging and committing

Stage relevant files by name - never `git add -A` or `git add .`, since that
risks pulling in unrelated changes.

Write the commit message to a temp file and commit with `-F`, rather than
`-m`, so multi-line bodies stay exactly as written:

```bash
cat > /tmp/odoo-commit-message.txt <<'EOF'
[TAG] module: short description

Optional body line.
EOF
git commit -F /tmp/odoo-commit-message.txt
```

Any equivalent temp-file flow works (PowerShell's `Set-Content`, an editor,
etc.) as long as the final commit is created with `git commit -F <file>`.

## Squashing before a PR

Per [OCA guidelines](https://github.com/OCA/maintainer-tools/wiki/Merge-commits-in-pull-requests#mergesquash-your-own-commits),
squash your own back-and-forth commits into one clean commit per logical
change before opening a PR - the rest of the world only needs the final state
and a clear summary, not the "fix bug 1", "fix bug 2" history.

- Single trailing fix → `git commit --amend` is enough (see above).
- Folding several commits into one → interactive rebase:

```bash
git rebase -i HEAD~N   # N = number of commits to fold
```

Keep the first line as `pick` with the real `[TAG] module: description`
message, and mark the rest `fixup` (drop their messages) or `squash` (merge
messages):

```
pick 1949129 [IMP] module: Introduce feature A
fixup d2cf643 Fix bug 1 of feature A
fixup 42bd9e8 Fix bug 2 of feature A
fixup 7f767d5 Fix bug 3 of feature A
```

Only rewrite commits that are still local/unpushed, or on a branch owned
solely by the current author - never amend or rebase shared history without
confirming with the user first.

## Pre-commit hooks

Do not bypass pre-commit hooks (no `--no-verify`). If a hook fails, fix the
underlying issue, re-stage the changes, and create the commit again.
