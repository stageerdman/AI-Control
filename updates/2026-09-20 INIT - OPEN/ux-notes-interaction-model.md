# UX Notes: Selection, Interaction Model, List Implementation

## 1. Click semantics

- **Single-click, project row**: selects it (single-selection, replaces prior selection). Row shows selected state. Sidebar (future phase) would populate here — for now, selection is still real and visible even with no sidebar, so the state isn't wasted.
- **Single-click, organizer row**: does NOT select in the project sense — it toggles expand/collapse. Give it its own transient "pressed" flash, not the persistent selection highlight, so organizers never look "selected" the way a project does. This is the one deliberate asymmetry in the model and it must stay obvious: projects are things you act on, organizers are things you open.
- **Double-click, project row**: this phase, no chat view exists. Double-click still performs the single-click select (already true from the first click) and then does nothing further — no error, no dead flash, no disabled cursor. Treat the second click as a no-op past selection. Do not build a placeholder screen; an absent action is invisible, a placeholder is a thing users will file bugs against. When chat ships, double-click starts owning "open," and nothing about today's behavior has to change to accommodate that.
- **Double-click, organizer row**: same as single-click (expand/collapse toggle) — collapse-then-reopen at most, never a second, different action. Organizers only ever have one verb.
- **Single-click, untouched folder**: untouched folders shouldn't be independently clickable rows at all in this dashboard — they're not projects or organizers, so they carry no action. If they appear in-tree (contained inside an organizer, unmarked), single-click is a no-op with no selection highlight, visually flat. Simplest fix if it feels weird: don't render them as list rows in the first place; that's a call for the row-anatomy designer, but interaction-wise, they take zero clicks worth of behavior.

## 2. Keyboard navigation

- **Up/Down**: moves through the flattened *visible* row list — collapsed organizers' children are skipped entirely, expanded ones are traversed in-line. One flat cursor, no modal "enter a level" concept. This matches Finder list view and avoids needing a separate keyboard mode for nesting.
- **Enter**: on a project row, same as double-click (opens chat once it exists; no-op today). On an organizer row, same as click — toggle expand/collapse. Never triggers a rename or a text-edit affordance; this app doesn't need inline rename here.
- **Right/Left arrow**: reserve these for expand/collapse on organizer rows (right = expand, left = collapse) — standard `NSOutlineView`/Finder convention. Don't overload Enter for this.
- **Escape**: clears selection back to none. Once the sidebar exists, Escape also dismisses it. No other Escape behavior is needed today.
- **Tab**: the list is a single tab stop; arrow keys move within it. Don't make each row individually tab-focusable — that breaks standard macOS list conventions and would make Tab useless for moving to a future search field or toolbar.

## 3. Hover / focus / selected states

Three states, three distinct treatments, because they can legally co-occur (a keyboard-focused row can be non-selected; a hovered row can be the selected one):
- **Hover** (mouse only): faint background tint, no border. Purely a "you're pointing here" affordance.
- **Keyboard focus** (list has focus, cursor is here): a focus ring/outline around the row, independent of fill — this is what lets focus and selection be visually distinguished even when they're the same row.
- **Selected** (click or Enter-confirmed): solid tinted background (the standard macOS accent-color selection fill), persists even when focus leaves the list (e.g., focus moves to sidebar or window becomes inactive — use the standard dimmed-gray "inactive selection" treatment, not full accent, per macOS convention).
Never rely on hover-tint and selection-fill being the same color at different opacities only — keep selection using the system accent color so it reads as "selected" independent of hover state layered on top.

## 4. Native component: `List` + `OutlineGroup`/disclosure sections, not custom `ScrollView`

Use SwiftUI `List` with hierarchical data via `OutlineGroup` (or `DisclosureGroup` sections manually driving `List`, if I need to mix "flat project rows" and "organizer rows with children" under one recency-sorted top-level order — `OutlineGroup` alone assumes uniform recursion, so realistically this becomes a `List` whose top-level rows are a hand-rolled `ForEach` over the merged/sorted array, with organizer rows internally using `DisclosureGroup`-style expand state, not true multi-level `OutlineGroup` recursion).

Justification: `List` gives selection, keyboard nav (arrows/Enter), hover states, right-click context-menu wiring, and inactive-selection dimming for free, matching every convention in §2–3 without reimplementing them. A custom `ScrollView`+`LazyVStack` would require hand-building all of that from scratch — selection highlighting, keyboard focus ring, VoiceOver — for a first-phase feature; that's effort spent on plumbing, not on the "one thing that matters" (a fast, obviously-native project switcher).

**Real risk**: `List`'s built-in row-selection and disclosure state don't compose cleanly with a manually sorted, mixed-type array — keeping organizer expand/collapse state in sync with `List`'s selection binding across re-sorts (when recency reorders rows) is the one place this can get fiddly and needs a small, deliberate state model (expanded-IDs as a `Set`, not per-row local `@State`) to avoid bugs when rows shift position.

## 5. Right-click and reserved badge space

- **Right-click selects first**, Finder-style: right-clicking an unselected row selects it (replacing any existing selection) before the context menu opens. Right-clicking an already-selected row leaves selection as-is. This guarantees the eventual context menu's actions ("AI," "Stop") always operate on an unambiguous single row, and it means single/double-click and right-click never fight over what's "current."
- **Reserve a fixed-width trailing slot** in the row layout now (even if empty/transparent this phase) for a future status badge/pin indicator. Deciding the slot's existence and width today — not its content — means later phases add a badge without reflowing every row's text or breaking existing hit-testing/click-target math for expand chevrons vs. row body.
