---
name: tenancy-invariants
description: Enforce tenant isolation invariants across API, database, cache, query keys, and background jobs. Owns scripts that scan for client-supplied tenant IDs, unscoped queries, and missing tenant boundaries in cache keys.
compatibility: opencode
---

## What I do

Detect and prevent tenant isolation violations. Every tenant-owned resource must be scoped by a trusted server-side tenant identity, never by a client-supplied identifier.

Reference: TENANT-001, TENANT-002, TENANT-003 in `configs/engineering/invariants.yaml`.

## When to use me

Use this skill when:

- Implementing any API endpoint that reads or writes tenant-owned data.
- Designing or reviewing a query key, cache key, or background job.
- Reviewing code that constructs a database query, an HTTP request to another service, or a WebSocket room name.
- Auditing an existing module for cross-tenant access risk.

Do NOT use this skill for pure UI work, build/CI work, or non-tenant-scoped infrastructure.

## Invariants enforced

| ID | Rule |
| --- | --- |
| TENANT-001 | Tenant authorization scope derives from trusted server-side context, never from request body / query / path params |
| TENANT-002 | Cache keys (TanStack Query, Redis, in-memory) include tenant identity |
| TENANT-003 | Cross-tenant admin operations are explicit, capability-gated, audited |

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/scan-client-tenant-input.mjs` | ast-grep for `req.body.company_id`, `body.tenant_id`, `query.tenantId`, etc. |
| `scripts/scan-unscoped-queries.mjs` | Detects ORM query builders missing tenant scope |
| `scripts/scan-query-keys.mjs` | TanStack Query / React Query keys missing tenant boundary |

Each script emits JSON lines on stdout, one finding per line:

```json
{"rule":"tenant/client-supplied-scope","severity":"error","confidence":0.97,"file":"src/foo.ts","line":82,"symbol":"createPart","evidence":"companyId: req.body.company_id","suggestedInvestigation":"derive company from authenticated workspace context"}
```

Severity model:

- `error` → block / fail CI
- `warning` → surface to author
- `advisory` → log only

## Workflow

1. **Run the scripts against the changed files** before declaring done:
   ```sh
   for s in configs/opencode/skills/tenancy-invariants/scripts/*.mjs; do
     node "$s" --workdir "$(pwd)" --changed-files <files...>
   done
   ```
2. **For each error finding, fix the root cause** — not the symptom.
   - If `req.body.company_id` is the issue, derive `company_id` from `req.context.session.companyId` instead.
   - If a query key is missing tenant scope, add the tenant ID to the key array.
3. **Add a test that would have caught the violation** (regression test in `tests/integration/<area>.tenant-scope.test.ts`).
4. **Verify** by running the script again — error count drops to zero.

## Anti-patterns to refuse

- "Add a try/catch around the cross-tenant access" — that's hiding the bug.
- "Move the tenant check to a different layer" — the rule is invariant; layering doesn't change it.
- "Use a database row-level security policy instead" — that may help but does not replace the application invariant.
- "The UI only shows tenant A's data so this can't happen" — UI filtering is not authorization.

## Related skills (do not load unless needed)

- `state-consistency` — overlap on canonical-ownership but focuses on UI state, not server tenant scope
- `architecture-fitness` — checks import-graph rules; complements but does not replace this
- `nox-ui-engineering` — UI invariants UI-001 through UI-004

## Output

When invoked on a task, return:

- Per-script: count of error / warning / advisory findings
- Each error finding with file:line and proposed fix
- Confirmation that regression tests exist for each error that was fixed
- Any invariants that should be added to `configs/engineering/invariants.yaml` based on observed patterns
