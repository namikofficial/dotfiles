# Tenant isolation rules

Reference for `tenancy-invariants`. Long-form explanation of the three invariants and how they apply in practice.

## Why these rules exist

A SaaS product that mixes tenant A's data into tenant B's response is a P0 incident. It is also the bug that reappears most often as AI agents refactor — because the agent sees `req.body.companyId` and assumes it is correct, or builds a query that omits tenant scope because the agent's local view doesn't surface the missing filter.

The rules below are designed to make tenant isolation failures visible at code-review time and at static-scan time, not at customer-incident time.

## TENANT-001 — Trusted tenant scope

The single source of tenant identity in any request is the **authenticated session** (decoded JWT, server-side session record, or capability token). Never read tenant ID from:

- `req.body.*`
- `req.query.*`
- `req.params.*`
- request headers like `X-Tenant-Id` (unless explicitly designed as a multi-tenant admin override per TENANT-003)
- the client side of any IPC channel

### Pattern to reject

```ts
// BAD — client-supplied tenant ID becomes authorization scope
app.get("/parts", (req, res) => {
  const companyId = req.body.companyId || req.query.tenant
  return partRepo.find({ where: { companyId } })
})
```

### Pattern to accept

```ts
// GOOD — tenant scope from session
app.get("/parts", (req, res) => {
  const companyId = req.context.session.companyId
  return partRepo.find({ where: { companyId } })
})
```

### Why this is enforced by an `error`-severity finding

Cross-tenant data access is a P0. We refuse to ship code that does this, full stop.

## TENANT-002 — Cache keys include tenant boundary

Any cache that stores tenant-owned data must key by tenant. Otherwise tenant A reads tenant B's cached value (or worse, writes over it).

### Patterns to reject

```ts
// BAD — query key omits company
useQuery({ queryKey: ["parts"], queryFn: fetchParts })

// BAD — Redis key omits company
redis.set("user-prefs", JSON.stringify(prefs))

// BAD — in-memory LRU omits company
lru.set(`user-${userId}`, value)
```

### Patterns to accept

```ts
// GOOD — tenant in the key
useQuery({ queryKey: ["parts", companyId], queryFn: fetchParts })

// GOOD
redis.set(`company:${companyId}:user-prefs`, JSON.stringify(prefs))

// GOOD
lru.set(`company:${companyId}:user-${userId}`, value)
```

### What `scan-query-keys.mjs` checks

- TanStack Query `queryKey:` arrays — do they include any variable that resolves to a tenant ID?
- `redis.set`, `cache.set`, `lru.set` calls — does the key string contain a company/tenant/workspace segment?

The script is conservative: it flags keys that *appear* to omit tenant scope. A manual review confirms whether the surrounding context makes it safe (rare).

## TENANT-003 — Cross-tenant admin operations are explicit

Support staff, internal tooling, and certain admin endpoints intentionally span tenants. These are dangerous if they leak outside their narrow use case.

Requirements:

- Capability check before any cross-tenant query (`canImpersonateTenant(actor, target)`)
- Audit log entry with: actor, target tenant, reason, timestamp
- The endpoint is gated behind a separate route prefix (`/admin/impersonate`, not `/api/parts`)
- Tests cover both the capability check (denied without capability) and the audit trail

The `tenancy-invariants` skill does not have a script for TENANT-003 because it's a code-review concern, not a static-scannable pattern.

## Working with the scripts

```sh
# Scan every TypeScript file in src/
node configs/opencode/skills/tenancy-invariants/scripts/scan-client-tenant-input.mjs \
  --workdir "$(pwd)"

# Scan only changed files (faster during development)
node configs/opencode/skills/tenancy-invariants/scripts/scan-client-tenant-input.mjs \
  --workdir "$(pwd)" \
  --changed-files src/domain/parts/PartService.ts src/api/routes/parts.ts

# Scan with grep-only mode (no AST — faster, less precise)
node ... --grep-only
```

Each script prints JSON lines on stdout. The agent-lab `security` grader consumes this output.

## When the scripts complain about legitimate code

Sometimes the pattern matcher is wrong. For example:

- A test that intentionally checks `req.body.companyId` is rejected by the auth middleware
- A schema definition that has a `companyId` field for documentation

For these, the right response is to **fix the test or schema to not match the pattern**, not to silence the scanner. If the pattern is genuinely too broad, open an issue against `scan-client-tenant-input.mjs` and add a `// tenancy-skip: <reason>` comment with a written justification.
