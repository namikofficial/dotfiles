---
name: runtime-evidence
description: Collect deterministic, minimally-interpretive evidence from the running system — browser events, network requests, server logs, DB queries, cache state, timings. Produces an evidence packet that `runtime-diagnosis` consumes.
compatibility: opencode
---

## What I do

Gather facts about a bug or behavior. I do NOT interpret them. The packet I produce is input to `runtime-diagnosis`, not a conclusion.

Why this separation matters: collection should be deterministic and reproducible; diagnosis is reasoning. Separating the two lets the same evidence be fed to multiple reasoners (M3, Nemotron, Luna) for independent conclusions.

## When to use me

Use this skill when:

- A user reports a bug that crosses the browser / API / DB boundary.
- A test is failing intermittently and you need ground truth about what actually happened.
- You're investigating a performance complaint (slow request, janky UI).
- You need to compare actual vs expected behavior without jumping to conclusions.

Do NOT use this skill for purely static analysis (read the code instead) or for design questions (no runtime to observe yet).

## The evidence packet

Every collection produces a JSON file shaped like this:

```json
{
  "evidence_id": "<uuid>",
  "collected_at": "<ISO-8601>",
  "collected_by": "runtime-evidence",
  "user_action": {
    "description": "Manager selects Warehouse A in the receive flow",
    "selector": "select[name='warehouse']",
    "value": "warehouse-a-id",
    "performed_at": "<ISO-8601>"
  },
  "browser": {
    "events": [
      { "type": "click", "target": "...", "timestamp": "..." }
    ],
    "console": [
      { "level": "error|warning|info|log", "message": "...", "url": "...", "line": 42 }
    ],
    "page_metrics": {
      "ttfb_ms": 120,
      "dom_content_loaded_ms": 350,
      "load_ms": 800
    }
  },
  "network": [
    {
      "url": "https://api.example.com/bins?warehouse=a",
      "method": "GET",
      "status": 200,
      "duration_ms": 95,
      "request_headers": { "...": "..." },
      "response_headers": { "content-type": "application/json" },
      "response_body_summary": { "count": 12, "first_id": "bin-001" }
    }
  ],
  "server": {
    "log_lines": [
      { "timestamp": "...", "level": "info|warn|error", "message": "...", "trace_id": "..." }
    ],
    "db_queries": [
      { "sql": "SELECT * FROM bins WHERE warehouse_id = $1", "duration_ms": 5, "params": ["warehouse-a-id"], "row_count": 12 }
    ],
    "cache_lookups": [
      { "key": "company:b:bins:warehouse:a", "hit": true|false, "duration_ms": 1 }
    ]
  },
  "client_state": {
    "tanstack_query_keys": [
      ["bins", "company-b", "warehouse-a"]
    ],
    "url_search_params": "?warehouse=warehouse-a",
    "local_storage_keys": ["activeWorkspace", "theme"],
    "useState_observed": [
      { "component": "BinSelector", "name": "selectedBin", "value": null }
    ]
  },
  "timings": {
    "user_action_to_first_byte_ms": 200,
    "first_byte_to_render_ms": 50,
    "total_round_trip_ms": 250
  },
  "correlation_ids": {
    "trace_id": "...",
    "span_ids": ["..."]
  },
  "limitations": [
    "Could not capture service-worker intercepted requests",
    "DB query log rotated before query captured"
  ]
}
```

## Workflow

1. **Use the browser MCP** to capture page state, console messages, network requests, and timing metrics.
   - `browser_navigate_page` to the page
   - `browser_press_key` / `browser_click` / `browser_fill` to reproduce the user action
   - `browser_list_console_messages` for console
   - `browser_list_network_requests` for network
   - `browser_take_screenshot` for visual context
2. **Use the configured server log forwarder** to capture `server.log_lines` and `db_queries`. If your product doesn't have one, write a minimal middleware that wraps requests with structured logging.
3. **Use the cache inspection tool** for `cache_lookups` (Redis MONITOR, TanStack Query devtools, etc.).
4. **Inspect client state** using browser DevTools or by exposing it through a dev-only query parameter.
5. **Write the packet** to `.ai/evidence/<scenario-id>-<timestamp>.json`.

## Rules

- Do not summarize, paraphrase, or interpret. Copy the actual response body field names, exact error messages, exact timings.
- Do not omit fields; use `null` for "not measured" and an entry in `limitations` to explain why.
- Do not skip steps because you "know" what the answer is. The whole point of this skill is the data.
- If a tool you need is unavailable (no DB query log, no tracing), record it in `limitations` and continue with what you have.

## Related skills

- `runtime-diagnosis` — consumes the packet this skill produces
- `regression-hunter` — uses the same packet shape but for "what changed"
- `differential-debugging` — uses the packet to discriminate between competing hypotheses

## Output

When invoked, return:

- The path to the evidence packet file
- A one-paragraph summary of WHAT was collected (not what it means)
- The list of `limitations` so the reasoner knows what gaps to fill
