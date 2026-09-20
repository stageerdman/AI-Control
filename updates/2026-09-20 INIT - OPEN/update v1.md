# INIT — Build AI Control

## Goal

Build AI Control: a native macOS app that removes the repeated setup work of
working with Claude Code across many projects (coding principles, `.md`
files, folder structures, secrets, update tracking), and gives a single
dashboard over every project with an embedded Claude Code session per
project. Full spec: `PROJECT.md`. Original brief: `idea.md`.

## Roadmap

- **Phase 0 — Bootstrap.** Git + GitHub (public), this project's own
  `updates/` tracking, a buildable-but-blank SwiftUI app shell.
- **Phase 1 — Core file model.** `AIControlNode` (project/organizer/
  untouched), `.project` frontmatter parsing, `FolderScanner` with nested-
  organizer detection, unit tests. Lives in a standalone `AIControlCore`
  Swift package so it's testable without Xcode/UI.
- **Phase 2 — Dashboard UI.** Mixed project/organizer list sorted by
  recency, search. UX-agent pass before building.
- **Phase 3 — Project sidebar.** Description, out-of-date flags, secret
  names, GitHub/git status, issues list.
- **Phase 4 — Terminal embedding.** SwiftTerm-based PTY session per project;
  app can send input and read output.
- **Phase 5 — Session management.** Pin running sessions, awaiting-input
  detection, stop routine, notifications.
- **Phase 6 — Global config.** `~/.ai-control/` modules/wiki/prompts/`.env`;
  CLAUDE.md generation and drift/rebuild.
- **Phase 7 — New project / adopt existing folder flows.**
- **Phase 8 — New update flow, secrets sync, out-of-date indicators
  end-to-end.**
- **Phase 9 — Polish.** Dock badge, notifications, Settings window for
  prompts.

## Status

**Phase 0, Phase 1, and Phase 2: done.**

Done:
- Repo initialized, pushed to `https://github.com/stageerdman/AI-Control`
  (public).
- This project's own tracking files created: `.project`, `.gitignore`,
  `issues.txt`, this update.
- `AIControlCore` Swift package built: `AIControlNode`, `ProjectFile`,
  `ProjectFileParser`, `FolderScanner`, `DashboardRow`, `DashboardListBuilder`.
- 28 unit tests written and passing (`swift test`), covering project/
  organizer/untouched/invalid-nested-organizer classification, frontmatter
  parsing, recency computation, and dashboard sorting/search/flattening.
- macOS app shell scaffolded via `xcodegen` (`App/project.yml`), depends on
  `AIControlCore`, builds with `xcodebuild`.
- Dashboard UI built and shipped: root-folder picker, mixed project/
  organizer/untouched list sorted by recency, live search, expand/collapse,
  keyboard navigation, uniform click-to-select across all row kinds, empty
  states. Three UX-specialist passes designed it before code was written
  (`ux-notes-list-architecture.md`, `ux-notes-search-recency.md`,
  `ux-notes-interaction-model.md`); real usage against a fixture folder then
  overrode several of their calls — see `wiki.md`.

Decisions made:
- Repo is public.
- Core domain logic (`AIControlCore`) is a separate Swift Package from the
  Xcode app shell, so it can be unit tested with `swift test` in isolation.
  See `wiki.md` for the full reasoning.
- Deployment target is macOS 14 (from 13) for `.onKeyPress`.
- Recency is folder modification time for now, not real chat history — see
  `wiki.md`.
- Nested organizers are classified as a distinct, non-interactive
  `.invalidNestedOrganizer` kind, not treated as organizers at all.
- Selection is uniform across every row kind (including organizers, which
  also toggle expand) — overriding the UX doc's original asymmetric design,
  per direct user feedback while testing. See `wiki.md`.

Next (Phase 3 — Project sidebar):
- Description, out-of-date flags, secret names, GitHub/git status, issues
  list for the currently selected row.
