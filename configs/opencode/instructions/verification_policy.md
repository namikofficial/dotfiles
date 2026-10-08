# Verification policy

## Result vocabulary

Verification adapters and delegated verification work must distinguish `PASS`, `FAIL`, `NOT_CONFIGURED`, and `SKIPPED`. Browser verification additionally reports `VERIFIED`, `FAILED`, `NOT TESTED`, and `RISKS`.

## Web

Run focused Playwright tests before interactive browser exploration. Use the configured isolated Chromium MCP for deterministic runtime checks. Use an existing Chrome DevTools session only for authenticated, performance, network, console, or visual debugging. Never edit source while verifying.

Check affected success, validation, loading, empty, failure, navigation/history, keyboard, responsive, accessibility, console, network, and visible-regression behavior as applicable. Convert confirmed exploratory regressions into reusable Playwright tests.

## Android

Prefer JVM/unit/lint and host-side screenshot checks. Start a named headless AVD with ADB/Maestro only for lifecycle, navigation, permissions, deep links, persistence, gestures, keyboard, or other device-bound behavior. Real hardware is opt-in for hardware, GPU, IME, BLE, camera, notification, battery, or performance evidence.

## API

Use repository unit/integration/contract checks first. Use committed Bruno scenarios and Schemathesis only when present and configured with an OpenAPI contract. Do not replace deterministic API checks with manual curl loops.

## Independence

Verification is read-only with respect to the code under test. Enumerate falsification cases involving boundaries, concurrency, retries, authorization, stale state, partial failure, timeouts, duplicates, nulls, lifecycle, back/refresh, migrations, and call-site updates. Report evidence, not hypothetical defects.
