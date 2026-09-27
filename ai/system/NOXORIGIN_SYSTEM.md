# NoxOrigin Mobile — AI Agent System Prompt

Built on: Expo 57, React Native 0.86, Tamagui 2.7, Reanimated 4.5, Expo Haptics.

## Stack identity

- **Tamagui** = NoxOrigin visual identity. Use for dashboard layouts, branded buttons/cards, metric surfaces, customer/invoice/task presentation, typography, spacing, and color tokens.
- **`@expo/ui`** = native interaction primitives. Use for bottom sheets, contextual menus, pickers, switch, slider, date/time, native forms, and platform-native transient UI.
- **Reanimated 4** = custom motion and gestures. Use for custom transitions and animations that are NOT native navigation or sheets.
- **Native navigation** = always prefer `expo-router` or native stack navigators over JS-side routing.

## Styling rules

1. Never add a new UI library (NativeWind, Paper, Gluestack, RN Reusables, etc.). The stack is intentionally chosen.
2. Spacing, radii, font sizes, and motion durations MUST come from Tamagui token tables. No raw pixel literals.
3. Reanimated worklet timing: `press` 90–120ms, `reveal` 180–220ms, `sheet` spring, `navigation` native, `success` spring + light haptic, `reorder` spring + medium haptic.
4. Respect `prefers-reduced-motion`. Disable non-essential animation when set.
5. Touch targets ≥44×44 CSS px for primary actions; ≥24×24 for secondary.

## Design language

### Anti-generic patterns

Reject without written justification:
- Pure-white background with single accent and Inter/Roboto defaults
- Hero section with gradient blob and "Welcome to X" copy
- Three feature cards in a row with outline icons
- Pill-shaped gradient buttons with soft drop shadow
- Identical `border-radius: 12px` everywhere
- Centered everything with `display: flex; justify-content: center`
- Long forms with 15 boxed inputs — use grouped sections with native pickers
- Loading = centered spinner only — use inline progress on the affected region
- Empty states = sad illustration only — explain + offer a recovery action

### UI hierarchy

- CRM list rows: native list, excellent typography, minimal containers
- Entity pages: strong surface header, metric row, primary/secondary actions, activity stream
- Create flows: one beautiful bottom sheet with grouped options + haptic on selection
- Finance surfaces: one dominant metric, tiny secondary metrics, soft sparklines, expandable drill-down via bottom sheets
- Notifications/inbox: swipe gestures (snooze/done)

### State coverage

Every interactive surface MUST handle: initial/loading/empty/partial/error/validation/permission-denied/offline/destructive-confirm/success.

## Expo-native components to prefer

`@expo/ui`: `BottomSheet`, `Menu`, `Picker`, `Switch`, `Slider`, `FieldGroup`, `List`, `Button`, `TextInput`, `Collapsible`.
`@expo/ui` backed by SwiftUI (iOS) / Jetpack Compose (Android) — prefer over JS-mocked controls.

Use `react-native-keyboard-controller` for CRM forms, search, comments, and task editing.

Use `Expo Haptics` for selection feedback, success, and reorder confirmation.

## NoxOrigin motion primitives

```
press       90–120ms
reveal      180–220ms
sheet       spring
navigation  native
success     spring + light haptic
reorder     spring + medium haptic
```

## UX writing rules

- Lead with what the user needs to know, not what the system did
- Destructive confirm names the target: "Delete Q3 Forecast? This removes 14 line items."
- Errors include recovery: "Couldn't save — your network dropped. Retrying automatically."
- Avoid: "Oops!", "Uh oh!", emoji as functional UI, exclamation marks in error states

## Accessibility (WCAG 2.2 AA)

- Every form input has a programmatically associated label — placeholder is not a label
- Errors associated via `aria-describedby`, announced via `aria-live="polite"`
- Focus always visible (≥3:1 contrast); never `outline: none` without replacement
- Color never the sole conveyor of information
- Dialogs: trap focus, return focus on close, labeled by heading, Escape closes

## When to invoke skills

- `mobile-design` — mobile feasibility, platform decisions, touch psychology
- `building-native-ui` — Expo Router, native tabs, navigation patterns
- `nox-ui-engineering` — building/reviewing screens, UX state matrices, design-to-code
- `emil-design-eng` — animation craft, interaction polish
- `anti-ui-slop` — hard finish gate against generic AI-generated UI
- `frontend-trace` — locate component entry points before editing

## Verification

Browser evidence required before claiming done. `expo start` renders are NOT proof — capture console, network, and relevant state screenshots.

Do not commit, push, or alter credentials. Runtime authentication remains user-owned.
