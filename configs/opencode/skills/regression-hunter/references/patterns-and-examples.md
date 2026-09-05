# Regression hunt reference: search patterns and examples

Each category has a search pattern and a worked example of a regression that snuck through.

## Category 1: changed defaults

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E '^\+.*default'
```

### Example regression

```diff
- const TIMEOUT_MS = 30_000
+ const TIMEOUT_MS = 5_000  // faster failure
```

Tests passed because they used 10s timeouts. Production saw hundreds of false timeout failures.

## Category 2: changed sorting

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'orderBy|sort|order:'
```

### Example regression

```diff
- ORDER BY created_at ASC
+ ORDER BY created_at DESC
```

A "newest first" change in a notifications list. Users who relied on chronological order for audit purposes lost the ability to find recent items at the bottom.

## Category 3: changed null behavior

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'null|undefined|optional'
```

### Example regression

```diff
- return parts.filter(p => p.warehouseId != null)
+ return parts.filter(p => p.warehouseId ?? null)
```

The first form excludes nulls; the second keeps them. Pagination changed from "exclude orphans" to "include orphans". Total page count changed.

## Category 4: changed permission behavior

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'permission|authorize|gate|require'
```

### Example regression

```diff
- if (!canRead(user)) throw new ForbiddenError()
+ if (!canRead(user, resource)) throw new ForbiddenError()
```

Missing the resource argument meant the function always returned true. Permission was effectively removed.

## Category 5: changed pagination

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'limit|offset|page'
```

### Example regression

```diff
- const DEFAULT_PAGE_SIZE = 100
+ const DEFAULT_PAGE_SIZE = 50
```

Cached responses from the larger page size returned more items than the new client expected. Some clients truncated; some crashed on unexpected array lengths.

## Category 6: changed serialization

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'JSON\.|toJSON|serialize'
```

### Example regression

```diff
- toJSON() { return { id, name } }
+ toJSON() { return { id, name, status } }
```

A new field added. Existing clients that deserialized into a strict shape (no unknown fields allowed) failed validation.

## Category 7: changed error status / codes

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'status\(|throw new'
```

### Example regression

```diff
- throw new HttpError(400, "validation failed")
+ throw new HttpError(422, "validation failed")
```

Client code that matched on `if (status === 400)` no longer triggered its validation-recovery flow.

## Category 8: changed retry behavior

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'retry|backoff'
```

### Example regression

```diff
- retries: 3, backoff: 'exponential'
+ retries: 1, backoff: 'fixed'
```

A "reduce load on upstream" change. Production saw transient failures become permanent.

## Category 9: changed responsive behavior

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E '@media|breakpoint|min-width|max-width'
```

### Example regression

```diff
- @media (min-width: 768px) { .sidebar { display: block } }
+ @media (min-width: 1024px) { .sidebar { display: block } }
```

Tablet users lost the sidebar. The "support more screen sizes" change was actually a regression.

## Category 10: changed keyboard behavior

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'onKeyDown|tabIndex|accessKey'
```

### Example regression

```diff
- <button onKeyDown={handleEnter} onClick={handleClick}>
+ <button onClick={handleClick}>
```

A "simplification" that removed the keyboard handler. Keyboard users lost the ability to activate the button with Enter.

## Category 11: changed accessibility semantics

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E 'aria-|role=|alt='
```

### Example regression

```diff
- <img src="..." alt="Shipment #1234" />
+ <img src="..." />
```

A "decorative image" change for an image that screen-reader users actually relied on.

## Category 12: changed i18n / copy

### Pattern

```sh
git diff HEAD~1..HEAD -- <file> | grep -E '^\+.*["'"'"']'
```

### Example regression

```diff
- <button>Save</button>
+ <button>Save changes</button>
```

A "more descriptive" change. Tests that matched the literal text broke. Translations became incomplete.
