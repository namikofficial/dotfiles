---
name: web-verification
description: Read-only browser verification with Playwright and evidence reporting.
compatibility: opencode
---

Use focused deterministic Playwright tests first. Only then use the configured Playwright browser MCP for runtime, visual, responsive, accessibility, console, or network checks. Do not edit source. Return `VERIFIED`, `FAILED`, `NOT TESTED`, and `RISKS`, including route, actions, expected behavior, observed behavior, and concrete evidence.
