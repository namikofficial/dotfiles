---
name: ui-ux-mobile-product-review
description: Review and improve UI, UX, product flows, React, React Native, and Android implementations with concrete evidence.
compatibility: opencode
---

# UI, UX, Mobile, and Product Review

Use this skill for web React, React Native, Android, Compose, XML layouts, or any request where the user experience matters.

## Workflow

1. Identify the user goal, primary flow, platform, screen, and affected component.
2. Trace the UI with LSP and CodeGraph before reading unrelated files.
3. Review hierarchy, navigation, information architecture, copy, affordances, feedback, and visual consistency.
4. Check loading, empty, error, offline, permission, retry, destructive-action, and success states.
5. Check accessibility: semantics, labels, focus, keyboard/switch navigation, touch targets, contrast, dynamic text, and screen-reader order.
6. For React, inspect props, hooks, state ownership, effects, render performance, and responsive behavior.
7. For React Native, inspect navigation, safe areas, platform branches, keyboard behavior, gestures, lists, permissions, deep links, and native modules.
8. For Android, inspect Compose/XML semantics, lifecycle, ViewModel state, configuration changes, back navigation, density, insets, permissions, and Gradle/build variants.
9. Use browser automation, screenshots, emulator evidence, or existing tests when available.
10. Report prioritized findings with exact paths, user impact, reproduction steps, and implementation-ready changes.

## Output

Return: user goal, current flow, critical UX issues, accessibility issues, platform issues, visual/design issues, recommended changes, affected files, and verification steps. Separate observed evidence from design recommendations.

