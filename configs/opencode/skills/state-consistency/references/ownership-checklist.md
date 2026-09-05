# State ownership checklist

Use this checklist when reviewing or designing a screen.

For each meaningful piece of state, fill in one row. If a row has more than one owner, the state is ambiguous and needs a canonical-owner decision.

## Screen: __________________

| State | Owner | Fallback / persistence | Notes |
| --- | --- | --- | --- |
| `auth.session` | server (cookie) | refresh on app load | |
| `activeWorkspace` | URL `?ws=` | localStorage backup | |
| `filters` | URL | none | filters must be shareable |
| `list.results` | TanStack Query | n/a | |
| `selectedRows` | URL | none | selected rows are a query, not local |
| `draftForm` | useState | IndexedDB if offline | |
| `lastViewedAt` | server | n/a | |
| `theme` | localStorage | n/a | |
| `featureFlag.X` | server | n/a | flags come from config endpoint |
| | | | |

## Ambiguity check

For each row above, ask:

1. Is this value readable from anywhere else? (`grep` for the variable name in src/, search the codebase for `localStorage.getItem` with related keys, look for duplicate `useState` hooks.)
2. If two sources of truth exist, which one wins? Is that documented?
3. When the canonical owner updates, do the duplicates get cleaned up?

If any answer is "no", the state is ambiguous.

## Migration plan

For each ambiguous state:

1. Pick the canonical owner (the one closest to the user-visible source of truth, usually URL or server).
2. Delete the duplicate(s). For localStorage entries: clean up on next read with a versioned schema.
3. Add a test that fails if the duplicate re-appears.

## Reconciliation policy

For each state that round-trips through multiple layers (offline draft, optimistic update):

1. What is the canonical order of writes? (local → server, server → local, both)
2. What happens on conflict?
3. When does the duplicate state get cleaned up?
4. Where is this policy declared? (ADR / comment in code / inline)

Document each. If undocumented, file an ADR.
