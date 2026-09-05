---
name: workflow-state-machine
description: Detect workflow-state fields in code, extract implicit state machines, assert illegal transitions are rejected, ensure state transitions write audit rows. For shipment, invoice, ticket, lead, payment, approval lifecycles.
compatibility: opencode
---

## What I do

Make implicit state machines explicit. Whenever the software contains a lifecycle — shipments that move through statuses, invoices that go from draft to paid, tickets that move through a workflow — there must be:

1. An explicit declaration of states and allowed transitions.
2. A single function (or method) that performs transitions.
3. Audit rows for every transition.
4. Tests for both legal and illegal transitions.
5. UI derived state computed from the current state, not stored separately.

Reference: STATE-001, STATE-002, STATE-003 in `configs/engineering/invariants.yaml`.

## When to use me

Use this skill when:

- Designing or reviewing a new entity with a lifecycle.
- Refactoring scattered `if (status === "x")` checks across a codebase.
- Auditing whether illegal transitions are reachable.
- Adding an audit log requirement.
- Designing the UI state derivation from a backend state.

Do NOT use this skill for entities without a lifecycle (e.g. free-form notes, single-page forms).

## Invariants enforced

| ID | Rule |
| --- | --- |
| STATE-001 | Workflow states have explicit transitions |
| STATE-002 | State transitions are auditable |
| STATE-003 | State transitions are idempotent under retry |

## Workflow

### 1. Find state fields

Run `scripts/extract-states.mjs` against the codebase. It produces a JSON map of every field whose name matches `status`, `state`, `phase`, `step`, `stage` etc. and groups them by entity.

### 2. Identify scattered transitions

For each state field, search the codebase for `if (status === ...)`, `=== "x"`, or `setStatus(...)` calls. The transitions should live in ONE place, not scattered.

### 3. Create the state machine module

Single file per entity, e.g. `src/domain/shipments/stateMachine.ts`:

```ts
import type { ShipmentState } from "./types"

export const STATES = [
  "DRAFT",
  "IN_TRANSIT",
  "RECEIVED",
  "COMPLETED",
  "CANCELLED",
] as const

export const TRANSITIONS: Record<ShipmentState, ReadonlyArray<ShipmentState>> = {
  DRAFT:       ["IN_TRANSIT", "CANCELLED"],
  IN_TRANSIT:  ["RECEIVED", "CANCELLED"],
  RECEIVED:    ["COMPLETED"],
  COMPLETED:   [],
  CANCELLED:   [],
}

export function canTransition(from: ShipmentState, to: ShipmentState): boolean {
  return TRANSITIONS[from]?.includes(to) ?? false
}

export function transition(
  shipment: Shipment,
  to: ShipmentState,
  actor: Actor,
  reason?: string,
): Result<Shipment, TransitionError> {
  if (!canTransition(shipment.state, to)) {
    return err({ code: "ILLEGAL_TRANSITION", from: shipment.state, to })
  }
  // write audit row, perform side effects, etc.
  return ok({ ...shipment, state: to })
}
```

### 4. Assert illegal transitions fail

Run `scripts/assert-illegal-transitions.mjs` against any test scenario. For every state pair NOT in the allowed map, there must be a test asserting the transition fails.

### 5. Audit log

Every successful transition writes an immutable audit row:

```
audit_log:
  id, entity_type, entity_id, actor_id, before_state, after_state, reason, created_at
```

The audit table does not have UPDATE or DELETE in any migration that touches it. Database role used by the app has INSERT-only on this table.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/extract-states.mjs` | finds `status`/`state`/`phase`/`step`/`stage` fields and groups by entity |
| `scripts/assert-illegal-transitions.mjs` | checks for tests of illegal transitions |

Both emit JSON lines on stdout.

## UI derivation

The UI should derive visible UI state from the backend state:

```tsx
function shipmentActions(s: Shipment): Action[] {
  if (s.state === "DRAFT") return [transition("IN_TRANSIT"), cancel()]
  if (s.state === "IN_TRANSIT") return [receive()]
  if (s.state === "RECEIVED") return [complete()]
  return []
}
```

Do NOT mirror the backend state into a separate UI field. The UI state is a function of the backend state.

## Anti-patterns to refuse

- Refactoring state transitions without the audit row.
- Adding new states by updating scattered `if` checks.
- Encoding states as `string` literals without a type-level enum.
- Allowing a "completed" entity to be moved back to "draft" implicitly because "the user can edit it".
- A separate UI state that drifts from the backend state because they were updated in different code paths.

## Output

When invoked on a task, return:

- Inventory of state fields discovered in the codebase
- For each: location of the single transition function (or warning if scattered)
- For each: list of illegal transitions and the test that asserts they fail
- Audit log coverage report
- UI derivation site locations
- Recommended changes with file:line and exact test additions
