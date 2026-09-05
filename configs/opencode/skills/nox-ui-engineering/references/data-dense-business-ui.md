# Data-dense business UI

Specialized guidance for screens that handle high-volume operational data: warehouses, bins, shipments, CRM records, invoices, tables, filters, status, bulk selection, permissions, workspaces, audits, operations.

This file is loaded by `nox-ui-engineering` when the screen under review is operational / data-dense rather than marketing / landing-page / single-task.

## Why this category matters

Most public frontend-design skills are obsessed with landing pages, hero sections, marketing sites, portfolio sites. Their advice ("use plenty of whitespace", "make the CTA prominent", "single-column layout") is wrong for operational UI.

Operational UI optimizes for:

- Information density (you can see more without scrolling)
- Bulk action efficiency (operations staff do the same task 50× a day)
- Status hierarchy (you can scan a row and know what needs attention)
- Filter/sort speed (you find the one row out of 2000)
- Audit trail clarity (you can answer "who did what when")

This reference collects rules specific to those goals.

## Density decisions

### Table vs cards decision

Default to **table**. Cards are appropriate only when:

- The entity has a single dominant image (product, person, project)
- The natural orientation is square and visually rich
- The user is browsing/discovering, not searching/sorting

Default to **table** when:

- There are ≥5 records on screen
- The user needs to compare rows
- Sort/filter is a primary action
- The data has multiple comparable columns (status, date, amount, owner)

If you default to cards for a 2000-row shipment list, the screen is wrong.

### Density modes

Pick the density mode BEFORE implementing. Do not mix:

| Mode | Row height | Use when |
| --- | --- | --- |
| **Compact** | 24-28 px | Power-user lists, warehouse ops, audit logs, terminal-style screens |
| **Standard** | 32-40 px | Default for most business apps |
| **Comfortable** | 48-56 px | Touch-first, kiosk, mobile, novice-user onboarding |

A shipment list should be compact. A first-time settings screen should be comfortable. Don't mix within one product without reason.

## Sticky columns

For wide tables, certain columns must be sticky:

- **Always sticky left**: the row identity column (id, name, code)
- **Always sticky right**: the action column (edit, delete, more)
- **Sometimes sticky**: status (so you can see the red rows as you scroll horizontally)

The sticky pattern must not break keyboard navigation. Test that arrow keys and Tab still work with sticky columns.

## Bulk selection

### Selection model

Choose one:

- **URL-addressable**: `?selected=id1,id2,id3` — survives refresh, shareable, addressable
- **Component state**: ephemeral, lost on refresh, fast to implement

For data-dense UI, prefer URL-addressable. The user can save their selection, share it, come back tomorrow and continue.

### Selection indicators

- Selected rows must be visually distinct from unselected (background, leading checkbox, accent border)
- The selection count must be visible at all times ("12 of 2,437 selected")
- A "select all on this page" checkbox in the header
- A "select all matching filter" option when the filter is active (with a count)

### Bulk action toolbar

When ≥1 row is selected, a bulk action toolbar appears:

- Position: bottom of screen OR sticky header; pick one, be consistent
- Actions: the 1-3 most common actions on the selected items (delete, archive, assign, export)
- Cancel/clear selection affordance
- Bulk actions that are destructive must require confirmation

### Selection survives pagination

If you bulk-select on page 1, navigate to page 2, then click bulk-delete — the user expects page 1's selections to still be active. Implement this explicitly; don't rely on TanStack Query's default cache behavior.

## Filter chips

- Active filters show as removable chips above the table
- Each chip shows the filter name + value + × (remove)
- "Clear all" action when ≥1 chip is active
- Hide chips if 0 active filters (don't show an empty chip row)
- URL-addressable: `?status=active&warehouse=brazil&owner=alice`

## Saved views

Power users want to save their filter + sort + column-selection combo:

- "My open shipments, sorted by age"
- "Inbound for warehouse Brazil, last 7 days"
- Save: name it, store it
- Load: dropdown of saved views, single-click to apply
- Manage: rename, delete, share with team

Saved views must persist per user across devices. Persist on the server, not just localStorage.

## Column customization

Let users pick which columns are visible, in what order:

- "Show/hide columns" menu
- Drag-to-reorder
- Column widths resizeable
- Persist per user (server-side, like saved views)

Don't force every column to be visible. Power users hide what they don't need.

## Pagination vs virtualization

| Approach | Use when |
| --- | --- |
| **Page-based pagination** | ≤200 rows typical, server-side filter/sort is necessary, save-state is per-page |
| **Cursor-based pagination** | Infinite scroll use case, server returns next cursor |
| **Virtualization (TanStack Virtual)** | >200 rows on screen, client-side filter/sort, fast scrolling required |

For warehouse ops with 2000+ shipments and frequent sorting, virtualize. Don't paginate a 2000-row list with 100 per page — the user has to click 20 times to scan it.

## Inline editing

Inline editing is appropriate when:

- The change is small (status toggle, quantity, owner reassign)
- The user can do it from the table view (no need to drill in)
- Confirmation is implicit (the new value is visible)

Don't inline-edit:
- Multi-field forms (use a modal or drill-in page)
- Anything requiring validation messages or undo
- Anything affecting more than one entity

## Master/detail layouts

Pattern: list on the left, detail on the right. Use when:

- The user frequently moves between list and detail
- The detail shows enough to be useful without drilling in further
- The list is the primary navigation

Don't use master/detail for:
- First-time discovery (no selection yet)
- Mobile (no horizontal space)

## Command palettes

A command palette (Cmd+K) is essential for power users. Surface:

- Navigate to screen
- Search for entity (jump to part #1234)
- Run action (create shipment, archive bin)
- Toggle feature flag

Keep it fast (<50ms to open). Index everything.

## Keyboard navigation

Operational UI must be keyboard-first:

- Arrow keys move row selection
- Space toggles row selection
- Enter opens detail
- `/` focuses search
- `Cmd+K` opens command palette
- `Escape` clears selection / closes modal
- Letter shortcuts (`n` for new, `e` for edit) when discoverable

Show keyboard shortcuts in tooltips. Don't hide them.

## Multi-select

For actions that affect multiple items, NEVER use a dropdown to pick "which one". Multi-select with checkboxes is the only acceptable UI for operational bulk operations.

## Query in URL

For any screen with filters, sort, pagination, or selection, ALL of that state belongs in the URL. This is non-negotiable for data-dense UI:

- Bookmark / share / email a filtered view
- Browser back/forward navigates between filtered states
- Refresh preserves the view

If your operational screen can't be linked to, it's broken.

## Persistent filters

A "sticky filter" model: filters the user sets once (e.g. "my warehouses only") should persist across navigation and across sessions. Don't reset every time the user opens the screen.

## Empty state distinctions

**Empty-filtered ≠ empty-dataset.** These are different:

- **Empty-dataset**: no data exists yet (e.g. no bins configured). Show: "No bins yet. Create one." + a clear CTA.
- **Empty-filtered**: data exists but the current filter excludes everything. Show: "No bins match your filters. [Clear filters]". No CTA to create — the user is filtering, not browsing.

Mixing these confuses the user. See `references/web.md` for the full UX state matrix.

## Status semantics

For operational data, status is the most scanned column. Pick a status model and stick to it:

- Mutually exclusive (one of: DRAFT, IN_TRANSIT, RECEIVED)
- Multi-flag (any of: archived, locked, starred)
- Phase-based (current phase + history)

Show status as:
- A colored chip with the label text
- Color: red for "needs attention" (overdue, blocked), yellow for "in progress", green for "complete/ok", gray for "neutral/no data"
- NEVER color-only — always include the label text. Color-blind users exist.

Sort by status when the user is looking for "what needs my attention" — overdue first, then due-today, then upcoming.

## Audit history

For operational entities that change over time (shipments, invoices, bins):

- Show recent history in the detail view (last 10 events)
- "View full history" link to a complete log
- Each event: who, what, when, why (if recorded)
- Don't show audit history on the list view — it clutters. Drill in to see it.

## Responsive degradation

Data-dense UI doesn't translate to mobile by stacking columns. Plan for it:

- Desktop: full table, all columns visible
- Tablet: hide 1-2 non-critical columns, keep density
- Mobile: replace table with a card-per-row summary view (1-3 most important fields)

Don't try to make the table itself responsive. Cards on mobile, table on desktop. Two implementations of the same data.

## Specific patterns

### Shipment list

- Columns: id, warehouse, status, last_movement_at, owner, weight
- Density: compact (32px row)
- Default sort: last_movement_at desc
- Filter chips: status, warehouse, owner
- Saved view default: "Active shipments for my warehouses, sorted by age"
- Bulk actions: assign, archive, export

### Invoice list

- Columns: id, customer, amount, status, due_date, days_overdue
- Density: compact
- Default sort: due_date asc (overdue at top)
- Status column: "OVERDUE" red chips are visually loud
- Bulk actions: send reminder, mark paid, export

### Warehouse layout / bin list

- Hierarchical view: warehouse → zone → bin → contents
- Expandable rows OR drill-in pages
- Real-time updates (a bin was just scanned): highlight the row briefly
- Bulk: assign, move, audit

## Anti-patterns

- Replacing a 2000-row table with cards "for visual appeal"
- Hiding the selection count
- Forcing every row to look identical when 95% are routine and 5% need attention
- Showing audit history inline on the list view (clutters)
- Resetting filters on every navigation
- Making the table itself "responsive" by stacking columns on mobile (use cards instead)
- Color-only status (red dot with no label)
- "Add new" as the only bulk action (operations staff rarely add new; they act on existing)
