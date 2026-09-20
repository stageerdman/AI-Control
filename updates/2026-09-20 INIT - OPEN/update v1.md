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

**Phases 0–5.1, Phase 6, and Phase 7: done (Phase 7 awaiting live verification).**

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

Phase 6 (Global config) — done:
- No isolated research experiment this time: it's file-model work like the
  existing scanning/git code, not a new external API (principle 3 applies to
  new APIs). A UX-specialist pass ran first for the two UI surfaces
  (`ux-notes-global-config.md`).
- **Core (`AIControlCore`, testable):** `GlobalConfig` model,
  `GlobalConfigLocator` (`~/.ai-control/`, `AI_CONTROL_HOME` override for
  tests), `GlobalConfigReader` (modules with mtimes, wiki pages with parsed
  usage descriptions, prompts, `.env` **key names only**), and a pure
  `ClaudeMdDriftDetector` (§6.3). +16 tests, **63 total pass**.
- **Prompt store + bootstrap (App):** `GlobalConfigStore` reads the repo and
  resolves routine-prompt text (stored file → built-in default);
  `RoutinePromptKind` holds the six §8.6 prompts. The hardcoded Stop prompt now
  flows through the store. First-launch **skeleton bootstrap** creates the
  dirs, seeds the default prompts, an empty `.env`, the wiki `search.sh`, a
  README, and runs `git init` — **module content stays AI-authored** (§7).
- **CLAUDE.md drift + Rebuild (App, §6.3/§8.2):** the sidebar's old "not
  available yet" Maintenance placeholder is now a real drift row (needs-config
  / needs-modules / not-generated / up-to-date / out-of-date + changed-module
  chips + **Rebuild**), driven by the detector. Rebuild sends the stored prompt
  into the **project's own session** (never the app editing files, §2), with
  honest async "Rebuilding…" feedback and self-heal from Claude's `.project`
  rewrite (re-read on activate / on rebuild finish). No status colour —
  `attentionRed` stays awaiting-input only.
- **Bootstrap strip:** a neutral (not red) "Create global config" strip on the
  dashboard while `~/.ai-control/` is absent; disappears once the skeleton
  exists. Builds; awaiting live verification.

Phase 6.4 (Global Config control window, from live feedback) — done:
- Live reaction: the "Create global config" strip created `~/.ai-control/`
  **silently and vanished** → confusing; the user wanted a real place to see and
  control the `.md` files/prompts ("a window like on the top bar… or at least let
  me open the folder and edit"). Two UX-specialist passes ran first
  (`ux-notes-config-window.md`, `ux-notes-config-content.md`).
- **Stores lifted to app scope.** `AIControlApp` now owns
  root/viewModel/session/globalConfig/alerts so a second scene shares them;
  `DashboardView` receives them. Adds **Settings… ⌘,** + **Window → Global
  Config** commands and a **gear toolbar button**.
- **Global Config window** (`NavigationSplitView`): Overview / Modules / Wiki /
  Prompts / Secrets / General — one window for all of `~/.ai-control/` (§8.5+§8.6
  folded together). MVP = honest live **visibility** + **Reveal in Finder /
  Open in editor** on every section (the reusable `ConfigFolderActions`);
  Default/Edited prompt badges; **Create lives here** with in-place feedback; the
  dashboard strip button is now **"Set up…"** and opens the window (fixes the
  silent-vanish). No status colour. In-app text editing deferred.
- **Option C chosen by the user** (AI interviews → drafts modules): new
  `authorModules` prompt + `TerminalSessionStore.authorModules(at:)` runs a
  root-scoped Claude session that interviews and writes UX/WORKFLOW/STRUCTURE/
  CODING; shown in a `DraftModulesSheet`; reload on close self-heals status to
  "Ready · n modules". App authors nothing (principles 2/7 intact — modules are
  the *input* the AI writes, not a project template; see wiki).
- **Live-verified (2026-09-20):** the top-bar **Global Config** menu opens the
  window; sidebar sections switch; Reveal/Open work; the **Draft modules with AI**
  interview runs and writes the four modules (Modules section then lists them).
  Fixes found live and applied: single top-bar menu (no gear); `List(selection:)`
  +`ForEach`+`.tag` so sidebar rows are clickable; robust Open-in-editor
  (falls back to Reveal); the interview now sends on a real *ready* signal (Claude
  booted + output quiet, 12s cap) instead of a fixed timer that raced startup; and
  the root interview session is excluded from awaiting-input alerts so it no longer
  fires a phantom "project is waiting for your reply."

Deferred from Phase 6 (by design):
- **Secret sync** row is still an honest placeholder — it shares this exact
  state machine but lands in Phase 8 (needs global-`.env`-vs-project diffing).
- **Settings-window** global-config status + prompt editing (§8.6) → Phase 9
  when that window exists; the dashboard strip covers the first-launch case now.
- **AI-authored module content** on first launch (§9.1 step 2) rides on the
  dashboard AI window (§8.4), not yet built; the skeleton + honest
  "needs global modules" states bridge until then.
- **Live-watching** module edits is currently a re-read on app-activate +
  post-rebuild rather than a recursive FSEvents watcher — enough for the flow,
  revisit if it feels stale in use.

Phase 7 (New project / adopt flows + AI window) — done, awaiting live test:
- Two UX-specialist passes first (`ux-notes-new-project.md`,
  `ux-notes-ai-window-adopt.md`).
- **Core:** `NewProjectValidator` (empty/invalid/taken name, empty description)
  + 8 tests → **71 total pass**.
- **New Project (§9.2):** a **New Project** toolbar button (gated on a connected
  root) + the empty-state action open a form sheet (`NewProjectSheet`): name /
  location (root or organizer) / visibility / required INIT description, live-
  validated. On submit the app creates the **empty** target dir and opens a keyed
  session there (`startNewProject`), sending the `newProject` prompt + a
  param/INIT appendix on `onReady`; the project opens full-window (`ProjectView`,
  synthetic node) so the build is watched live; rescan-on-return surfaces the row.
- **AI window (§8.4):** a dedicated `Window("AI")` scene (top-bar **AI** menu,
  ⌘\\, and auto-raised by AI actions) hosting one persistent root-scoped session
  via `aiWindowSession(rootURL:)`, tracked in `globalSessionURLs` so it never
  pins/notifies — this also retires Phase 6's "phantom notification" rough edge.
  Header shows a **reference chip** (folder handed in) with clear/▢ + path
  tooltip.
- **Right-click "Ask AI…"** on every row (`RowRightClick` now always pops a menu;
  Stop/Force Close appended when running). Behavior branches on kind: untouched →
  `adopt`, invalid-nested → `fixNesting`, project/organizer → editable pre-filled
  reference line.
- **Adopt/fix (§9.3):** the sidebar **Bring under AI Control** / **Let AI fix it**
  buttons now send the report-first `adopt` prompt (+ path / fix appendix) to the
  AI window instead of revealing in Finder; captions updated. The AI reports a
  verdict, applies on the user's "yes" (principle 2), and the dashboard rescans
  on the AI-session idle tick so the row reclassifies.
- Builds; app authors nothing (the only app writes are the empty New-Project dir
  and, earlier, the config skeleton — structure, never content).

Live-test flags carried from the specs: **pre-fill-without-submit** (the general
Ask-AI line typed via `send()` without Enter) is unverified against the real
`claude` TUI — if it collapses into a paste pill, fall back to auto-sending the
short reference line. A dedicated `fixNestedOrganizer` prompt is deferred (reuses
`adopt` + fix appendix). FSEvents live-refresh still deferred (rescan on
return/activate/AI-idle-tick for now).

Still deferred (not Phase 5 scope):
- The one-shot working→awaiting entry *pulse* animation — left to tune during
  live testing (the static arrow + reorder already ship).
- Editable routine prompts (the Stop prompt) → Settings window, §8.6 / Phase 9.
- Deferred project-view work (§8.3): side panel with recent updates,
  how-to-use/status, `issues.txt`, and the New-Update button.
