# List Architecture & Visual Hierarchy — Dashboard (Phase: single mixed list)

## 1. Row anatomy

One row height, one template, three data states — never three layouts. Each row: leading glyph (20pt, fixed column) → name (primary, `.headline`/body-emphasized) → status/description snippet (secondary, truncated, single line) → trailing recency stamp (tertiary, monospaced-digit, right-aligned). That's it. No thumbnails, no colored chips, no badges — this phase carries zero session-state UI.

- **Project row**: `folder.fill` in accent tint (the app's one accent color, reserved for "this is a live project"). Subtitle = the project's description/status text.
- **Organizer row**: `folder` (outline, not filled) plus a disclosure chevron in the leading column ahead of it. Subtitle = "N projects" count, not free text — organizers don't have descriptions, so don't fake one.
- **Untouched-folder row**: `folder.badge.questionmark`, glyph and name rendered in plain secondary gray (no accent), subtitle = "Not under AI Control" in tertiary gray, no recency stamp (there's nothing to timestamp).

The glyph fill/outline/badge distinction is the entire language: filled = managed unit of work, outline = container, badge = unmanaged. No color-coding beyond the one accent, because color as a third signal on top of shape is redundant and gets noisy at 200 rows.

## 2. Expand/collapse

Disclosure chevron (`chevron.right` rotating to `chevron.down`, standard NSOutlineView-style) sits left of the organizer's folder glyph. On expand, child project rows insert directly beneath it, indented one fixed step (16pt, same indent macOS Finder/Mail use for hierarchy) — no nested card, no boxed container, no background tint. It's a flat scrolling list that grows/shrinks in place; nothing else moves except reflow. Indentation alone communicates containment — a visual box around children would imply organizers are a separate zone from projects, which contradicts "one list, mixed."

Expansion state persists per-organizer across launches (last thing a user does before quitting shouldn't reset on reopen).

## 3. Nested-organizer edge case

Flag it inline, not with a dialog or banner: the child organizer's row gets a small tertiary-gray caption appended to its subtitle — "Nested inside another organizer" — plus its folder glyph gets a thin dashed outline instead of solid. No red, no warning triangle, no alert icon: this is a structural oddity to notice, not an error to fear. It stays sorted by recency like everything else; the flag is informational, not a demotion.

## 4. Empty states

- **No root folder connected**: the list area is replaced entirely (not an empty list with a placeholder row) by a single centered composition: large `folder.badge.plus` glyph, one line — "Point AI Control at a folder" — and the one button that matters, "Choose Folder." No secondary explanatory paragraph; the icon and verb say it all.
- **Root connected, nothing inside**: different message, same layout skeleton, so the user isn't confused about whether the app is broken — centered `tray` glyph, "This folder is empty," with a lighter secondary line: "Add a project folder to get started." No button here (there's nothing to click that isn't already Finder's job).

Distinguishing these two states matters because they mean different things: one is "I haven't set the app up," the other is "the app is working, your folder just has nothing in it yet."

## 5. Density and grouping

Stays a single flat list at every scale, 5 rows or 200 — no date-grouping, no A–Z sections, no pinned/recent split. Grouping would fight the spec's core promise ("ordered by recency of last chat") by re-imposing a second axis of organization the user didn't ask for. Density: a compact single-line row (~32-36pt) with tight vertical padding, so 200 items stays scannable in one scroll rather than demanding pagination or search-first navigation — recency ordering plus the standard system search field (owned elsewhere) is sufficient wayfinding at any scale.
