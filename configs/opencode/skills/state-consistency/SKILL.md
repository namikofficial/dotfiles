---
name: state-consistency
description: Enforce canonical ownership of UI state across URL, client (component useState), server (TanStack Query), persistence (localStorage/IndexedDB), and offline (optimistic / pending sync). Detect ownership ambiguity and duplicate state.
compatibility: opencode
---

## What I do

Make state ownership explicit and unambiguous. Every meaningful piece of UI state must have exactly one canonical owner. Derived state must be computed, not stored. Mirrored state eventually drifts and causes bugs.

Reference: UI-002 in `configs/engineering/invariants.yaml`.

## When to use me

Use this skill when:

- Designing a new feature with both server data and local UI state.
- Reviewing a refactor that touches query keys, useState, or URL params.
- Debugging a bug where "the UI shows the wrong value after X".
- Implementing filters, selection, drafts, optimistic updates, or offline persistence.

Do NOT use this skill for purely backend state or for ephemeral UI state (hover, focus, scroll position).

## Invariants enforced

| ID | Rule |
| --- | --- |
| UI-002 | Each meaningful piece of state has ONE canonical owner |

## The ownership table

For every meaningful piece of state, declare the owner explicitly. Common categories:

| State | Canonical owner (typical) |
| --- | --- |
| `auth.session` | server (cookie + JWT decode) |
| `activeWorkspace` | URL (search param) OR server (last-used) |
| `list.filters` | URL (search params) |
| `list.results` | TanStack Query (server state) |
| `selectedRows` | URL (search param `?selected=id1,id2`) OR component useState (session-only) |
| `draftForm` | component useState OR IndexedDB (offline) |
| `lastViewedAt` | server |
| `theme` | localStorage |
| `featureFlag.X` | server (config endpoint) or build-time |

The owner for each row should be one of:
- URL (`searchParams`)
- Server (`useQuery` / `useSWR` / React Query)
- Component (`useState` / `useReducer`)
- Persistence (`localStorage` / `IndexedDB`)
- Offline queue (IndexedDB / service worker)

## Anti-patterns to refuse

- `useState` that mirrors `useQuery` data. (Derived from server state; read from the query.)
- `useEffect` that fetches into local state. (Use `useQuery`.)
- A `filters` object in `useState` AND a `?filter=...` URL param. (Pick one.)
- An optimistic update that lives only in component state, with no rollback path.
- A "drafts" feature that persists to localStorage AND syncs to the server AND lives in component state, with three different update paths.

## Workflow

### 1. Inventory state

For the screen under review, list every meaningful state and its owner. Use `references/ownership-checklist.md` as the template.

### 2. Detect ambiguity

For each state, ask: "where else does this value live?" If the answer is "in two places" or "in the URL AND in localStorage AND in component state", you have ambiguity.

### 3. Resolve

For each ambiguous state:
- Pick ONE canonical owner.
- Remove the others (delete the `useState`, remove the localStorage entry, drop the URL param).
- Make the migration safe (existing localStorage values get cleaned on next read).

### 4. Add a guard

If the state must round-trip through multiple layers (e.g. offline draft → server), declare the round-trip explicitly:

```ts
const draft = useDraftInIndexedDB(id)        // canonical: IndexedDB
const { mutate } = useSaveDraft(id)          // write path
const syncQueue = useOfflineQueue()          // pending mutations

return draft.status === "synced"
  ? <SyncedDraft data={draft.data} />
  : <PendingDraft data={draft.data} syncQueue={syncQueue} />
```

## Query keys

For TanStack Query, every input that affects the returned data must be in the key:

```ts
// GOOD
useQuery({ queryKey: ["parts", companyId, filters], queryFn: ... })

// BAD
useQuery({ queryKey: ["parts"], queryFn: ... }) // companyId missing
useQuery({ queryKey: ["parts", filters], queryFn: ... }) // companyId missing
```

Tenant-invariants scans this. If it flags a query key as missing scope, fix the key.

## Optimistic updates

An optimistic update must declare its rollback. The pattern:

```ts
const { mutate } = useMutation({
  mutationFn: updatePart,
  onMutate: async (changes) => {
    await qc.cancelQueries({ queryKey: ["parts", companyId] })
    const previous = qc.getQueryData(["parts", companyId])
    qc.setQueryData(["parts", companyId], (old) => ({ ...old, ...changes }))
    return { previous }
  },
  onError: (_err, _changes, ctx) => {
    if (ctx?.previous) qc.setQueryData(["parts", companyId], ctx.previous)
  },
})
```

The `onMutate` saves the previous value; `onError` restores it. Without the rollback, the optimistic update leaks.

## Offline reconciliation

Persisted offline state must define what happens on reconnect:

1. Server is the source of truth.
2. Client-side queued mutations replay in order.
3. Conflicts (server already has a newer version) must surface to the user, not silently overwrite.
4. After successful reconciliation, the local persisted state is dropped.

The state-consistency skill does not implement offline reconciliation itself; it requires that the implementation declare the reconciliation policy in a comment or ADR.

## Output

When invoked on a task, return:

- The ownership table for the screen under review
- For each ambiguous state: which owner is canonical, and what to delete
- For each offline / persisted state: the reconciliation policy
- For each query: confirmation that the key includes tenant scope and all data-affecting inputs
- List of `useState` calls that mirror server state (to delete)
- List of optimistic updates without rollback paths (to fix)
