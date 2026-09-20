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

**Phase 0, Phase 1, Phase 2, Phase 3, Phase 4, and Phase 5: done.**

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

Phase 5 (Session management) — done:
- Delivered early via live feedback (kept): auto-launch `claude` on session
  open; running sessions pinned on top with a green indicator (§8.1);
  right-click a project to act on a running session. Also fixed then: the
  single-click lag (double-click detected by timing) and the sidebar's
  per-click `git` call (GitHub info from `.project`).
- **Awaiting-input detection via Claude Code hooks** (the §11 architecture
  decision — hooks, not output-parsing). Research-first per principle 3: an
  isolated `phase5-experiment/` proved that an app-owned `--settings` file can
  register `Stop`/`UserPromptSubmit`/… hooks that write per-project status
  files, and that `bypassPermissions` works from that same file
  (`phase5-research.md`). `SessionHooks` (App) ships the hook + writes per-
  project settings; `StatusDirectoryWatcher` watches the status dir;
  `SessionStatusParser` + `SessionActivity` (AIControlCore, 7 tests) turn the
  files into typed state. `TerminalSessionStore` publishes `awaitingInputURLs`.
- **Dashboard surfacing** (§8.1): awaiting rows show an accent
  `arrowshape.right.fill` ("your turn") vs. the calm green running dot, in the
  same reserved 16pt slot; awaiting sessions sort above working ones in the
  pinned group. A UX-specialist pass designed it first.
- **Notification + Dock badge** (§11): `SessionAlerts` fires one `.active`
  notification per working→awaiting transition (withdrawn on leaving,
  suppressed when you're viewing that project) and sets the Dock badge to the
  awaiting count. Clicking a notification opens the project.
- **Stop routine** (§7/§9.7): right-click **Stop** interrupts, sends the
  wrap-up prompt, waits for the `Stop` hook, then `/exit`s and closes;
  **Force Close** keeps the immediate kill. 300s timeout backstop.
- **Auto-permission** (§11): Claude launches with
  `--dangerously-skip-permissions` — no approval ceremony (§4). (The settings
  file's `bypassPermissions` works headlessly but gates the interactive TUI;
  see Phase 5.1 / `wiki.md`.)
- **Live-verified by the user (2026-09-20):** auto mode launches with no
  prompts, the red glow reads well, and the graceful **Stop routine works** both
  mid-task and while Claude is asking a question (Esc → wrap-up prompt → commit/
  push → exit). Logic-level pieces are unit-tested (47 total).

Phase 5.1 (attention affordances, from live feedback) — done:
- Fixed from the first live test: auto mode now uses
  `--dangerously-skip-permissions` (the settings-file `bypassPermissions` pops
  an acceptance + trust gate in the interactive TUI); re-added the
  `Notification` hook so mid-task questions count as awaiting.
- **Red attention banner** (§8 spirit): a thin full-bleed banner above both
  screens when a non-foreground session awaits — "Go there" / "Show" / X.
  Consolidated (one banner for N projects); X dismisses per episode.
- **Red row glow**: a blurred red rim on awaiting rows (one entry swell then
  steady; Reduce-Motion aware) as an ambient reminder that outlives banner
  dismissal. One `Color.attentionRed` used nowhere else. A UX-specialist pass
  designed both first.
- **Live-verified (2026-09-20):** the red glow is "perfect"; banner + Stop
  confirmed working, including multiple simultaneous awaiting sessions.

Two mid-flight Stop bugs found and fixed during live testing (see `wiki.md`):
Claude's TUI interrupts on **Esc** (not Ctrl-C) and submits on **`\r`** (not
`\n`), and — because of its **paste detection** — the Enter must be sent as a
**separate keystroke** after the prompt, or a long prompt is typed but never
submitted.

Still deferred (not Phase 5 scope):
- The one-shot working→awaiting entry *pulse* animation — left to tune during
  live testing (the static arrow + reorder already ship).
- Editable routine prompts (the Stop prompt) → Settings window, §8.6 / Phase 9.
- Deferred project-view work (§8.3): side panel with recent updates,
  how-to-use/status, `issues.txt`, and the New-Update button.
