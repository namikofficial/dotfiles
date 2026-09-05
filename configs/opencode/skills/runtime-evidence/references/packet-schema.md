# Evidence packet reference

The full shape of a runtime-evidence packet, with notes on what each field means and how to capture it.

## Top-level

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `evidence_id` | string | yes | UUID, unique per packet |
| `collected_at` | string | yes | ISO-8601 timestamp |
| `collected_by` | string | yes | Always `"runtime-evidence"` |
| `user_action` | object | yes | What the user did to trigger the bug |
| `browser` | object | yes | Browser-side evidence |
| `network` | array | yes | Every HTTP request during the action |
| `server` | object | yes | Server-side evidence (logs, DB, cache) |
| `client_state` | object | yes | What state the client had at the moment of failure |
| `timings` | object | yes | Round-trip timings |
| `correlation_ids` | object | yes | trace_id, span_ids, request_id |
| `limitations` | array | yes | Anything you could not capture and why |

## user_action

```json
{
  "description": "User clicked the 'Save' button in the receive flow",
  "selector": "button[type='submit']",
  "value": null,
  "performed_at": "2026-09-02T08:14:22.123Z"
}
```

The `selector` should be a stable selector (data-testid preferred, fallback to semantic CSS). `value` is for form inputs.

## browser.events

Every event between `performed_at` and the action completing or failing. Include type, target (selector), timestamp.

## browser.console

Every console message. Do not filter. The reasoner decides which ones matter.

## browser.page_metrics

Performance API metrics from `performance.timing` or `PerformanceObserver`:

- `ttfb_ms` — Time to first byte
- `dom_content_loaded_ms`
- `load_ms`
- `largest_contentful_paint_ms` if available
- `cumulative_layout_shift` if available

## network

Every HTTP request during the action, with:

- Full URL (including query string)
- Method
- Status
- Duration
- Request headers (omit `cookie` for privacy)
- Response headers
- Response body summary — for JSON, include the top-level keys and lengths; for HTML, just the content-type and size. NEVER include the full body unless it is the failure point.

## server.log_lines

Structured log lines. Each line should include timestamp, level, message, trace_id, span_id.

## server.db_queries

Every database query executed during the action. Capture:

- SQL text
- Duration
- Params (omit PII)
- Row count

This requires DB query logging at the application level. If unavailable, record the limitation and skip.

## server.cache_lookups

Every cache read/write during the action. Capture key, hit/miss, duration.

## client_state.tanstack_query_keys

The set of query keys currently in the TanStack Query cache at the moment the action completed. Use `@tanstack/react-query-devtools` or queryClient.getQueryCache().getAll().

## client_state.url_search_params

The full search string at the moment of the action (after any client-side updates).

## client_state.local_storage_keys

The keys present in localStorage. Do NOT include the values.

## client_state.useState_observed

Hardest to capture without dev tools. Either:
- Expose useState values through a dev-only data attribute (`data-state="..."`)
- Use React DevTools inspector (snapshot)
- Add temporary debug code, capture, revert

## timings

| Field | Meaning |
| --- | --- |
| `user_action_to_first_byte_ms` | When the user clicked to when the first HTTP response byte arrived |
| `first_byte_to_render_ms` | When the first byte arrived to when the UI reflected the result |
| `total_round_trip_ms` | Sum of the above |

## correlation_ids

Every distributed-tracing ID you can capture. `trace_id` ties browser, server, and DB together.

## limitations

Anything you could not capture:

- "DB query log was rotated before the query ran"
- "Service worker intercepted this request before the network panel saw it"
- "TanStack Query devtools not enabled in this environment"
- "Could not reproduce on Safari"

These matter because they shape what the reasoner can and cannot conclude.

## Privacy

- Strip cookies, authorization headers, and PII from captured data.
- If a response body contains user data, record only the shape (top-level keys, array lengths), not the contents.
- Treat the packet as sensitive — store under `.ai/evidence/` which is gitignored.
