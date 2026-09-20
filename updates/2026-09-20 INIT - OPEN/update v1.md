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

**Phase 0, Phase 1, Phase 2, Phase 3, and Phase 4: done.**

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

Phase 3 (Project sidebar) — done:
- Core: `GitStatus` model + pure `GitStatusParser` (parses `git status
  --porcelain=v2 --branch` + a nul-separated one-line `git log`) + thin
  `GitStatusReader` that runs read-only `git` via `Process`. 12 new tests
  (9 parser, 3 reader integration against a temp repo, skipped if git is
  absent); 40 total pass.
- UI: right-hand `HSplitView` detail pane driven by the dashboard
  selection, with four kind-specific variants + an empty state. A UX
  specialist pass designed it first, respecting the honesty constraint —
  see `wiki.md`. Reusable components under `App/AIControlApp/Sidebar/`.
- Project variant shows: description, a live Git section, secret-name
  chips (names only), honest "not available yet" placeholders for
  CLAUDE.md drift / secret sync / chat-token activity, and `.project`
  details. Git status read off-main-thread with a token guard.
- Deferred as designed (honest placeholders, no faked status): CLAUDE.md
  drift + secret sync (need global config, Phase 6), last chat + tokens
  (need session-log parsing, Phase 10 data), and the untouched-folder
  "Bring under AI Control" flow (Phase 9.3 — reveals in Finder for now).

Phase 4 (Terminal embedding) — done:
- Research-first per CLAUDE.md principle 3: an isolated `phase4-experiment/`
  SPM package pulled SwiftTerm so its real API could be read from source;
  findings + build gotchas in `phase4-research.md`.
- SwiftTerm 1.20.0 added to `App/project.yml`; terminal code lives in the
  **App target** (AppKit), keeping `AIControlCore` UI-free.
- `TerminalSession` (+ `TeeingTerminalView`) owns one
  `LocalProcessTerminalView`, launches `$SHELL -l` in the project folder,
  and exposes **send input** (`send(_:)`) and **read output** (a
  `dataReceived` tee into a bounded `recentOutput`) — the two §11 abilities.
- `TerminalSessionStore` keeps one session per project URL so it **survives
  navigation** (§11). `ProjectView` shows the terminal full-area on
  double-click with a Back control; single-click still drives the sidebar.
- Build needs two flags/steps: `-skipPackagePluginValidation` and a
  user-installed Metal toolchain (agent's shell can't download it).

Phase 5 (Session management) — partially delivered early via live feedback:
- DONE: auto-launch `claude` on session open (configurable
  `TerminalSession.autoLaunchCommand`); running sessions pinned on top with
  a green indicator (§8.1); right-click a project for Open/Close Session
  (`TerminalSessionStore.runningURLs` + `stopSession`, `TerminalSession.stop`
  + `onTerminated`).
- Also fixed from feedback: the single-click lag (removed the count:2 tap
  gesture; double-click now detected by timing) and the sidebar's per-click
  `git` call (GitHub info now comes from `.project`; the tested GitStatus
  reader stays for the project view).
- STILL TODO for Phase 5: awaiting-input detection (via the `recentOutput`
  tee or Claude Code hooks) + its badge/notification, the Stop *routine*
  (graceful "wrap up and save" prompt vs. the hard Close), Dock badge, and
  the auto-permission flag for `claude` (§11).
- Deferred project-view work (§8.3): side panel with recent updates,
  how-to-use/status, `issues.txt`, and the New-Update button. `issues.txt`
  belongs here, not the single-click sidebar.
