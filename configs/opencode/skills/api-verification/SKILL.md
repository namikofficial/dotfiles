---
name: api-verification
description: Read-only API verification using repository tests, Bruno, and Schemathesis when configured.
compatibility: opencode
---

Run the repository's focused API checks first. Use Bruno scenarios and Schemathesis only when the repository has the required configuration and OpenAPI contract. Report missing capabilities as `NOT_CONFIGURED` and preserve reproducible failure evidence.
