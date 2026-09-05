# Diagnosis walkthrough: stale bins after workspace switch

A worked example showing the diagnosis skill applied to a real bug.

## The user report

> "After I switch workspace, the bins dropdown still shows bins from the previous workspace."

## Evidence packet (collected by runtime-evidence)

```json
{
  "user_action": {
    "description": "User selected workspace 'Operations (Brazil)' from the workspace switcher",
    "selector": "select[name='workspace']",
    "value": "company-b-id",
    "performed_at": "2026-09-02T08:14:22.123Z"
  },
  "browser": {
    "console": [
      { "level": "info", "message": "Workspace changed to company-b-id", "url": "/bins", "line": 0 }
    ],
    "page_metrics": { "ttfb_ms": 120, "dom_content_loaded_ms": 350, "load_ms": 800 }
  },
  "network": [
    {
      "url": "https://api.example.com/bins?company=company-b-id",
      "method": "GET",
      "status": 200,
      "duration_ms": 95,
      "response_body_summary": { "count": 0, "first_id": null }
    },
    {
      "url": "https://api.example.com/bins?company=company-a-id",
      "method": "GET",
      "status": 200,
      "duration_ms": 30,
      "response_body_summary": { "count": 12, "first_id": "bin-001" }
    }
  ],
  "server": {
    "log_lines": [
      { "timestamp": "...", "level": "info", "message": "GET /bins company=company-b-id count=0", "trace_id": "abc123" }
    ],
    "db_queries": [
      { "sql": "SELECT * FROM bins WHERE company_id = $1", "params": ["company-b-id"], "row_count": 0, "duration_ms": 5 }
    ],
    "cache_lookups": [
      { "key": "company:company-a-id:bins", "hit": true, "duration_ms": 1 }
    ]
  },
  "client_state": {
    "tanstack_query_keys": [
      ["bins", "company-a-id"]
    ],
    "url_search_params": "?workspace=company-b-id",
    "local_storage_keys": ["activeWorkspace"],
    "useState_observed": []
  },
  "timings": {
    "user_action_to_first_byte_ms": 200,
    "first_byte_to_render_ms": 50,
    "total_round_trip_ms": 250
  },
  "correlation_ids": { "trace_id": "abc123" },
  "limitations": ["DB query log only captured first query of the burst"]
}
```

## Diagnosis

**Most likely boundary: client-state.** Confidence: 0.85.

### Hypothesis H1: stale TanStack Query cache

- **Boundary:** client-state
- **Supporting evidence:** `client_state.tanstack_query_keys` shows only `["bins", "company-a-id"]`. After the workspace switch, the new query key `["bins", "company-b-id"]` should be in the cache. It's not.
- **Supporting evidence:** `network[0]` shows the new request `?company=company-b-id` returned 200 with count=0 — the server did receive and answer the new query.
- **Contradicting evidence:** none.
- **Cheapest discriminating test:** Open React Query devtools and check the query cache state. If only `company-a-id` is present, this is confirmed.
- **Confidence:** 0.85

### Hypothesis H2: query key missing tenant scope

- **Boundary:** client-state / code
- **Supporting evidence:** H1 suggests the query key uses `company-a-id` even after the switch — this is the same pattern the `tenancy-invariants` skill flags.
- **Contradicting evidence:** The network log shows the request DID include `company=company-b-id`, so somewhere the company ID is being read correctly. So the query key was constructed using the new company, but the cache was not invalidated.
- **Cheapest discriminating test:** grep for the query key construction: `queryKey:.*bins`. Check whether the company ID is in the key array.
- **Confidence:** 0.7

### Hypothesis H3: stale localStorage

- **Boundary:** client-state / persistence
- **Supporting evidence:** `local_storage_keys` includes `activeWorkspace`. If the app reads the active workspace from localStorage on mount but doesn't react to changes, this could be the issue.
- **Contradicting evidence:** the network log shows the new company ID was sent, so the app DOES know about the switch.
- **Cheapest discriminating test:** Watch the network panel during a workspace switch. If the new company ID is in the request URL, localStorage is not the bottleneck.
- **Confidence:** 0.2

## Recommended next action

Open `src/features/bins/queries.ts`. Verify the query key includes the active company. Add an invalidation on workspace change:

```ts
useEffect(() => {
  queryClient.invalidateQueries({ queryKey: ["bins"] })
}, [activeWorkspace])
```

Also: extract a `useBinsQuery(companyId)` hook that takes companyId as a parameter, so the query key is forced to depend on it.

## Open questions

- Why does the cache have `["bins", "company-a-id"]` at all after the switch? Did the app navigate to /bins on first mount with company-a, then switch to company-b, and never invalidate? That's the canonical state-consistency bug.
- Should the workspace switcher invalidate ALL query keys, not just bins? Probably yes, but that's a broader change.
