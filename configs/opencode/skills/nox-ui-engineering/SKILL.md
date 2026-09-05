---
name: nox-ui-engineering
description: Build and review UI with deliberate visual direction, complete UX state coverage, accessibility, design-language capture, and browser-runtime verification. Single entry point that replaces having several overlapping frontend/UX/a11y skills loaded at once.
compatibility: opencode
---

## What I do

Plan, implement, and review user interfaces end-to-end. I fuse:

- **Visual direction** (typography, spacing, color, motion, anti-AI-generic patterns)
- **UX state matrix** (loading / empty / partial / error / success / validation / destructive / offline / permission)
- **Accessibility** (semantics, keyboard, focus, ARIA, WCAG 2.2 AA)
- **UX writing** (labels, helper text, errors, empty states, destructive-action copy)
- **Design-language capture** (DESIGN.md as a product-specific contract derived from real source)
- **Design-to-code** (screenshot / Figma / reference ingestion → tokens → components)
- **Runtime verification** (browser DevTools + Playwright evidence before claiming done)

I am deliberately opinionated. I do not ship a UI that has only the "happy path" implemented.

## When to use me

Use this skill when the task is any of:

- Building or restyling a screen, component, surface, panel, dialog, form, or empty state
- Reviewing UI work for visual, UX, or accessibility defects
- Translating a screenshot, Figma frame, or visual reference into code
- Onboarding a new product area and there is no DESIGN.md yet
- Auditing whether a screen handles every state it should

Do not use this for purely backend, CLI, IPC, or schema work — those have dedicated skills.

## Principles

1. **No screen ships with a single state.** A screen is a matrix of states; one is not enough.
2. **Generic is the failure mode.** If the design could be mistaken for any other AI-generated product, redo it. Pick a deliberate aesthetic direction and commit.
3. **A11y is interaction, not a checkbox.** A screen is not accessible if a keyboard user cannot reach the primary action or a screen-reader user cannot recover from an error.
4. **Tokens, not magic numbers.** Spacing, radii, font sizes, and motion durations must come from a token table. If you typed a literal in a component, you leaked.
5. **Browser evidence is required.** "It compiles" and "it renders" are not proof. Show the page in a real runtime, capture console, network, and a screenshot of the relevant state.
6. **Less UI, better UI.** No decorative elements that don't carry meaning. No modal inside a modal. No icon button without a label.

## Anti-AI-generic-UI checklist

Reject any of the following without a written reason:

- Pure-white background with a single accent color and Inter/Roboto by default
- Hero section with a gradient blob and "Welcome to X" placeholder copy
- Three feature cards in a row, each with an outline icon, a heading, and a one-liner
- Pill-shaped gradient buttons with a soft drop shadow
- Identical `border-radius: 12px` on every card, button, and input
- Centered everything with `display: flex; justify-content: center; align-items: center;`
- Tailwind utility soup with no semantic class structure
- Mock data with `lorem ipsum` or `John Doe`, `item 1`, `item 2`
- A modal for everything that could be inline
- Loading states that are a centered spinner and nothing else
- Empty states that are a single sad illustration with no recovery action

If you produce any of these, explain why in the review. If you cannot justify it, change it.

## UX state matrix

Every interactive surface MUST specify behavior for each state below. "Same as happy path" is not acceptable.

| State | Trigger | Required UI elements |
|---|---|---|
| Initial / cold | First load, no cache | Skeleton matching the real layout, not a generic spinner |
| Loading | Known data is in flight | Inline progress indicator on the affected region, no layout shift |
| Empty | No data exists yet | Explanation of what would be here + the action that creates one |
| Partial | Some data loaded, some failed | Loaded items render correctly + failed items show a retry affordance |
| Error | The call failed | What failed, why in plain language, retry, contact/escalate |
| Validation | Invalid input | Inline field error, summary at submit, focus first invalid field, do not clear other fields |
| Permission denied | AuthZ failure | What was blocked, why, what to do, escape hatch if appropriate |
| Offline | No network | Banner, queue indicator, disable destructive actions |
| Destructive confirm | About to delete / remove / revoke | Plain-language confirmation naming the target object, undo or recovery path if any |
| Success | Action completed | What changed, what happens next, where to go |

For each state: provide the exact copy, the visual treatment, and the a11y behavior.

## Accessibility (WCAG 2.2 AA, not "score 100")

Per-screen checklist before any "done":

- Every interactive element is reachable by Tab in logical order; no focus traps
- Focus is always visible (≥3:1 contrast against adjacent colors); never `outline: none` without a replacement
- All form inputs have a programmatically associated label (`<label for>` or `aria-labelledby`); placeholder is not a label
- Errors are associated with their field via `aria-describedby` and announced via `aria-live="polite"`
- Dialogs trap focus, return focus on close, are labelled by their heading, escape closes
- Color contrast ≥4.5:1 for body text, ≥3:1 for large text and UI components
- No information conveyed by color alone (icons or text must accompany)
- Touch targets ≥24×24 CSS px; recommended 44×44 for primary actions
- `prefers-reduced-motion` respected; non-essential animation disabled
- Language attribute set on `<html>`; dynamic content changes announced
- Lists, headings, landmarks are semantic; no `<div>` soup where a `<ul>` or `<section>` is meant

If a screen fails any of these, it is not done. Do not ship.

## Design before JSX (substantial new UI / major redesigns)

For any non-trivial UI work — new screen, major redesign, anything that takes more than a few hours — implement this pre-flight BEFORE writing code. The discipline is the difference between an interface that looks intentional and one that looks AI-generated.

```
1. Visual thesis
   One sentence: what makes this screen feel different from every other screen in the product?
   Examples: "instrument panel for warehouse operators", "patient intake form for clinic staff",
   "table-first density for power users", "calm, minimal, single-task focus".
   If you cannot write this sentence in 15 seconds, you don't understand the screen yet.

2. Information hierarchy
   What is the primary action? What is secondary? What is tertiary?
   Which user task does this screen exist for? Everything else is decoration.
   Decision: one primary action, visible without scrolling. Tertiary actions collapse or hide.

3. Density
   Target density for the screen type:
   - Data table / inventory / shipment list → dense (8px row height, compact type)
   - Dashboard / overview → medium
   - Marketing / onboarding / empty state → sparse
   Do NOT use the same density across the whole product. Density is a deliberate choice per screen.

4. Typography
   Pick the type sizes and weights for THIS screen from the token scale, not from defaults.
   - Display / hero: largest scale, single weight
   - Headings: 2-3 sizes, 1-2 weights
   - Body: ONE size, ONE weight, defined line-height
   - Numbers in tables: tabular figures, monospace alignment if the column demands it

5. Component rhythm
   Decisions made BEFORE writing code:
   - Cards vs flat list vs table — pick one, not all three
   - Inline editing vs modal vs separate page — pick one
   - Filter chips vs sidebar filter vs URL-only — pick one
   - Toolbar actions: where do they live, what order, primary first

6. Rendered reference concept
   BEFORE writing JSX:
   - Produce a visual concept: either a wireframe, a static HTML/CSS mock, a screenshot of
     a reference design, or a clear ASCII layout sketch.
   - The concept must show the screen in each UX state (loaded, empty, error, validation,
     destructive confirm, offline).
   - Use `ui-ux-pro-max` or `ui-ux-pro-max` only as inspiration; never copy.

7. Critique the concept
   Run through the anti-AI-generic-UI checklist (above). If the concept matches any item,
   fix the concept, not the eventual code.
   Run through the UX state matrix. Are all states designed, not just the happy path?
   If the screen involves data tables or bulk operations, run the data-dense checklist
   (see references/data-dense-business-ui.md).

8. THEN implement
   Only after the concept passes critique do you write code.
   Implementation tokens (colors, spacing, radii, motion) come from tokens, not literals.
   If the implementation deviates from the concept, fix the code OR fix the concept.
   Never let the implementation drift to generic patterns.

If you skip this pre-flight and go straight to code, you will produce a generic AI-generated screen.
The pre-flight is the discipline that prevents that.
```

## UX writing

Copy is part of the UI. Apply these rules:

- **Lead with what the user needs to know**, not what the system did
  - Bad: `Error 422: Unprocessable Entity`
  - Good: `Email is already in use. Try signing in instead.`
- **Empty states explain and offer the next action**
  - Bad: `No projects.`
  - Good: `No projects yet. Create one to start tracking work.`
- **Destructive actions name the target**
  - Bad: `Confirm delete? [Cancel] [Delete]`
  - Good: `Delete "Q3 Forecast"? This removes 14 line items and cannot be undone.`
- **Helper text is concrete**
  - Bad: `Enter a valid value`
  - Good: `Use 8+ characters with a number and a symbol.`
- **Errors include the recovery**
  - Bad: `Save failed.`
  - Good: `Couldn't save — your network dropped. We'll retry automatically when you're back online.`
- **Avoid**: `Oops!`, `Uh oh!`, `Just`, `Simply`, `Easy`, exclamation marks in error states, emoji as functional UI

Strings should be externalized for localization from day one. No hard-coded English in components.

## Design-language capture (DESIGN.md)

A `DESIGN.md` at the product root is the persistent contract for how that product looks and behaves visually. It is the visual equivalent of `AGENTS.md`.

When invoked on a product that lacks `DESIGN.md`:

1. Inspect the actual source — do NOT invent a system
   - Find every color, font, radius, spacing, shadow, motion duration reference
   - Look at the existing screens; what is consistent across them?
   - Identify the most common patterns and the deliberate exceptions
2. Produce `DESIGN.md` with the following sections, each anchored to real file paths:
   - **Typography** — fonts, scale, weights, line heights, with usage rules
   - **Color** — semantic tokens (`surface`, `onSurface`, `primary`, `danger`, `success`, `warning`), not raw hex
   - **Spacing** — base unit, scale (e.g. `4 / 8 / 12 / 16 / 24 / 32 / 48`), allowed values
   - **Radius** — permitted radii and when to use each
   - **Elevation / shadows** — levels (e.g. `1` flat → `4` dialog), with what triggers each
   - **Motion** — durations, easing, reduced-motion behavior
   - **Surface hierarchy** — what sits above what, where layering is allowed
   - **Components** — the canonical Button, Input, Card, Dialog, Toast with their token references
   - **Do / Don't** — concrete examples taken from the real codebase
3. Verify every claim by pointing at a file and line. If you can't, drop the claim.

When modifying an existing product, the DESIGN.md is the source of truth. If you want to change it, change the contract AND the components together; do not let them drift.

## Design-to-code bridge

When the task starts from a screenshot, Figma frame, mockup, or visual reference:

1. **Ingest the reference** with the vision model; capture: layout grid, type scale, color palette, spacing rhythm, component shapes, motion hints
2. **Extract design tokens** — same shape as DESIGN.md sections
3. **Map to existing tokens first** — if the product has a DESIGN.md, prefer its tokens; only deviate with a written reason
4. **Plan the component hierarchy** — break the screen into primitives (Card / Button / Input / List / Dialog) BEFORE writing code
5. **Implement with tokens, not literals** — every color, spacing, radius references a token
6. **Verify in browser** — screenshot the result and compare against the reference; iterate at the token layer, not by tweaking literals

Do NOT write CSS-in-JS or Tailwind classes with raw hex / pixel literals. That is design debt.

## Runtime verification gate

Before claiming any UI work is done, capture browser evidence for the relevant states:

1. **Page loads** without console errors or unhandled promise rejections
2. **Network requests** return the expected payloads (status, shape, auth headers)
3. **Each state from the UX state matrix** is reachable and renders as specified — happy, loading, empty, error, validation, permission, offline, destructive confirm, success
4. **Keyboard navigation** traverses the primary flow end-to-end with visible focus
5. **Responsive behavior** at the breakpoints the product targets
6. **A11y quick pass** — tab through, verify focus order, verify labels and errors are announced
7. **Visual regression** — at least one screenshot per state, archived under `.ai/screenshots/<date>/<screen>/<state>.png`

Use the browser MCP (`browser_navigate_page`, `browser_take_snapshot`, `browser_take_screenshot`, `browser_list_console_messages`, `browser_list_network_requests`, `browser_press_key`, `browser_resize_page`). Playwright tests are preferred when the project already has them.

A build, a `cargo check`, a successful reload, a DOM assertion, or a screenshot of only the happy path is NOT proof. The state matrix must be observable.

## Output format

When this skill completes a task, return:

- **Goal & acceptance criteria** — restated in one sentence each
- **Surface touched** — exact files added / changed
- **States covered** — explicit list mapped to the UX state matrix; anything not covered is a residual risk
- **A11y evidence** — focus order confirmation, label associations, contrast check, motion check
- **Tokens used** — which DESIGN.md sections the implementation references
- **Browser evidence** — paths to screenshots and console/network captures
- **Open risks** — what was NOT verified and why

If any of these are missing, the work is not done.

## Related skills (do not load unless needed)

- `frontend-trace` — locate the screen / component entry point first
- `bug-repro` / `test-failure-debug` — when something is broken before you can implement
- `ui-ux-mobile-product-review` — independent critique from a reviewer perspective
- `docs-update` — refresh DESIGN.md and component docs when design system changes
- `conventional-commit` — for the resulting commit
