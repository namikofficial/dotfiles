---
name: regression-hunter
description: Specifically search for backward-compatibility damage in a change. Different from adversarial review: hunts for changed defaults, changed sorting, changed null behavior, changed permission behavior, changed pagination, changed serialization, changed error status, changed retry behavior, changed responsive behavior, changed keyboard behavior.
compatibility: opencode
---

## What I do

Answer the question: **what used to work that no longer works?**

I'm not looking for "is this implementation correct" (that's `adversarial-reviewer`). I'm looking for **silent regressions** — behavior changes that pass tests but break real users.

## When to use me

Use this skill:

- Before merging any non-trivial change.
- Before declaring a refactor "done".
- After a customer reports "X worked yesterday".
- During a release readiness review.

Do NOT use this skill for new features (no prior behavior to regress).

## The 12 regression categories

For every change, search for damage in each category. Use the exact search patterns below.

### 1. Changed defaults

```sh
git log -p --diff-filter=M -- <file> | grep -E '^\+.*default|^\-.*default'
git diff HEAD~1..HEAD -- <file> | grep -E '^\+.*default'
```

Look for: new default values, removed defaults, defaulted parameters added.

### 2. Changed sorting

```sh
rg 'sort\(' --type ts -C 2
git log -p -- <file> | grep -E 'orderBy|sort|order:'
```

Look for: ORDER BY changes, comparator changes, .sort() without explicit comparator (which differs between v8 versions).

### 3. Changed null behavior

```sh
rg '\?\?|\|\||\.nullable|allowNull|notNull' --type ts -C 1
git diff HEAD~1..HEAD -- <file> | grep -E 'null|undefined|optional'
```

Look for: `??` added (changes undefined → default), `?.` removed (was optional, now required), allowNull changes, NOT NULL added.

### 4. Changed permission behavior

```sh
rg '\.can\(|capability|permission|authorize' --type ts -C 2
git diff HEAD~1..HEAD -- <file> | grep -E 'permission|authorize|gate|require'
```

Look for: removed permission checks, added permission checks, capability changes, role changes.

### 5. Changed pagination

```sh
rg 'limit|offset|skip|take|cursor' --type ts -C 1
git diff HEAD~1..HEAD -- <file> | grep -E 'limit|offset|page'
```

Look for: page size changes, offset-to-cursor migrations, default limit changes, removed pagination.

### 6. Changed serialization

```sh
rg 'JSON\.(stringify|parse)|toJSON|serialize' --type ts -C 1
git diff HEAD~1..HEAD -- <file> | grep -E 'JSON\.|toJSON|serialize'
```

Look for: new fields in toJSON, removed fields, snake/camel changes, date format changes, null serialization changes.

### 7. Changed error status / codes

```sh
rg 'throw new|status\(|HttpStatus|ErrorCode' --type ts -C 1
git diff HEAD~1..HEAD -- <file> | grep -E 'status\(|throw new'
```

Look for: status code changes (200 → 201, 400 → 422), error message changes clients might match on, error code renames.

### 8. Changed retry behavior

```sh
rg 'retry|backoff|attempts|maxRetries' --type ts -C 2
git diff HEAD~1..HEAD -- <file> | grep -E 'retry|backoff'
```

Look for: retry count changes, backoff curve changes, removed retries, added idempotency key requirements.

### 9. Changed responsive behavior

```sh
rg '@media|breakpoint|min-width|max-width' --type css --type ts -C 2
```

Look for: breakpoint changes, container query changes, removed breakpoints.

### 10. Changed keyboard behavior

```sh
rg 'onKeyDown|tabIndex|accessKey|shortcut' --type ts -C 1
```

Look for: removed keyboard handlers, changed key bindings, changed tab order, focus traps removed.

### 11. Changed accessibility semantics

```sh
rg 'aria-|role=|alt=' --type tsx --type html -C 1
```

Look for: removed ARIA attributes, changed roles, removed alt text, removed labels.

### 12. Changed i18n / copy

```sh
git diff HEAD~1..HEAD -- <file> | grep -E '^\+.*["'"'"']' | head -50
```

Look for: changed user-visible strings (might affect translations, screenshots, screenshots diff, support docs).

## Output

```markdown
# Regression hunt: <change id>

## Category 1: changed defaults
- <finding> — file:line — confidence
- ...
## Category 2: ...
...
## Category 12: changed i18n / copy
- ...

## Critical findings (act before merge)
- ...

## Important findings (likely act before merge)
- ...

## Notes (informational)
- ...

## Tests that should be added
- ...
```

Each finding includes: file:line, what changed, why it might be a regression, suggested action.

## Anti-patterns

- "The tests pass" — tests don't cover backward compatibility; that's the whole point.
- "Nobody uses X anymore" — assume someone does until you have data.
- "It was a bug; the old behavior was wrong" — maybe, but customers depended on the buggy behavior. Confirm before changing.
- "We added a deprecation warning" — a warning is not a removal. Clients that ignore warnings will break.

## Workflow

1. **Run all 12 category searches** against the diff. Use `git diff HEAD~1..HEAD` (or the planned diff).
2. **For each hit, classify** as critical / important / informational.
3. **For each critical finding, recommend** either: revert, deprecate properly (with version + migration path), or document the breakage.
4. **For each important finding**, recommend: add a test, add a CHANGELOG entry, or document the change.
5. **Run before merge** — this skill should block merges that contain unhandled critical findings.

## Related skills

- `adversarial-reviewer` — finds implementation bugs. I'm about backward compatibility.
- `change-impact` — finds missing consumers. I'm about changed behavior.
- `nox-ui-engineering` — UX-level regressions. I'm about functional regressions.

## Output

When invoked, return:

- The 12-category report above
- A list of critical findings that block merge
- A list of recommended tests to add before the next regression cycle
