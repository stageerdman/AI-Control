# UX notes — the AI window + the right-click "AI" / adopt flow (§8.4, §9.3)

Design spec (no code). Covers two connected things:

- **A) The dashboard AI window** — a root-scoped Claude Code session for general
  questions and for handling untouched / invalid folders.
- **B) The right-click "Ask AI…" action + the adopt/fix flow** — how any row
  hands its folder to that window, and how the two interim sidebar buttons
  ("Bring under AI Control", "Let AI fix it") become real.

Principle 2 stays intact throughout: **the AI analyzes and changes files via the
CLI; the app only opens the session and types prompts/paths into it.** Every
mechanism below is built from patterns that already ship in the app.

---

## A) The dashboard AI window

### Recommendation: a dedicated `Window` scene, not a sheet

We already have the technical seed — `DraftModulesSheet` (in
`GlobalConfigWindow.swift`) hosts a root-scoped Claude session in a terminal and
reloads on Done. But a **sheet is the wrong container** for the AI window: a
sheet is modal-ish and blocks the dashboard, while §8.4 wants the AI window to
**stay available** while the user keeps clicking around, right-clicking rows, and
watching the dashboard update as folders get adopted.

The app already has the exact right pattern for a persistent, reopenable,
non-modal companion surface: **the Global Config `Window` scene**
(`AIControlApp.swift` → `Window("Global Config", id: GlobalConfigWindow.windowID)`
with the shared stores injected). Model the AI window identically:

```
Window("AI", id: AIWindow.windowID) {
    AIWindow(sessionStore: sessionStore, rootFolderStore: rootFolderStore)
}
```

- **Reuse, not reinvent:** the window's body is essentially `DraftModulesSheet`'s
  body — a header row + `TerminalContainerView(session:)` filling the rest. Lift
  the header/terminal chrome out of `DraftModulesSheet` into a shared little
  view; the module-authoring sheet and the AI window then share it.
- **Multi-scene store injection:** pass the same `TerminalSessionStore` /
  `RootFolderStore` instances the App already owns at `@StateObject` scope
  (the lesson "lift shared stores to the `App`, inject into every scene" — this
  is a third consumer of that pattern, no new wiring shape).
- **Opened / raised from three places**, all via the `openWindow(id:)`
  environment action already used for Global Config:
  1. A **dashboard toolbar button** labeled **"AI"** (icon `sparkles`), next to
     "Choose Folder…" in `dashboardBody`'s `.toolbar`.
  2. A **menu-bar entry** — a top-level `CommandMenu("AI")` with
     **"Open AI"** (mirror the existing `CommandMenu("Global Config")`). Give it
     a shortcut (e.g. `⌘\``) if free.
  3. **Automatically**, whenever a right-click "Ask AI…" or a sidebar adopt/fix
     action fires (see part B) — the window opens/raises so the user sees the
     reference land.

### The session behind it

- **One shared session, cwd = the connected root folder** (`rootFolderStore.rootURL`),
  obtained through a new store method `aiWindowSession(rootURL:)` that mirrors
  `authorModules(at:)`: ensure `session(for: rootURL)` exists, **add it to
  `globalSessionURLs`**, and return it — but *without* auto-sending any interview
  prompt. It's just a persistent Claude session at the root.
- **`globalSessionURLs` is what makes it "not a project."** Because the root
  session is in that set, `recomputeAwaitingInput()` already excludes it: **no
  dashboard pin, no green/awaiting indicator, no notification, no Dock badge.**
  This directly resolves the Phase-6 "known rough edge (MVP)" note in the wiki
  — the root/global session finally has a first-class home (§8.4) instead of
  leaking into the project awaiting-input machinery.
- **Distinct from `authorModules`:** that session is keyed on `config.root`
  (`~/.ai-control`); the AI window is keyed on the *project* root
  (`/dev`-style). Different URLs → different sessions → no collision. Both live
  in `globalSessionURLs`.
- **Relation to per-project sessions:** per-project sessions (keyed by project
  URL) keep everything they have today — pin, indicator, notifications, Stop /
  Force Close, the full-window project view. The AI window session is the
  *general* one: questions that aren't about a specific open project, and
  folders that **have no session of their own** (untouched / invalid — they
  aren't projects yet). Clean division of labor; nothing about the existing
  project flow changes.

### AI window layout (reuses the sidebar/`DraftModulesSheet` vocabulary)

```
┌───────────────────────────────────────────────────────────┐
│ ✦ AI · <root folder name>                                   │  header (SidebarHeader style)
│   General questions and folder analysis, at <root path>     │  caption
│                                                             │
│   Reference: ▢ my-app  ✕        ← chip, only when a folder   │  reference chip row
│                                    reference is active       │
├───────────────────────────────────────────────────────────┤
│                                                             │
│                 TerminalContainerView(session)              │  the real Claude CLI
│                                                             │
└───────────────────────────────────────────────────────────┘
```

- **Header:** `SidebarHeader(systemImage: "sparkles", isAccent: true, name: "AI", caption: <root path>)` — same component the Global Config window uses, so it looks native to the app.
- **Reference chip** (the visible-feedback surface, see part B): a small pill
  showing the **name** of the most-recently-referenced folder, full path as
  tooltip, with a `✕` to clear. Updated on every AI action. This is *app chrome*,
  independent of the CLI — so even before Claude responds, the user sees their
  right-click landed. (Honors the standing lesson: **every action needs visible
  feedback.**)
- **Empty state helper** (shown above/around the terminal until the first
  reference): one calm line —
  *"This session runs at your root folder. Right-click any folder and choose
  Ask AI to pull it in as a reference."*
- **No Done button** (unlike the sheet) — the window just stays open; close it
  like any window. The session survives (it's held by the store), so reopening
  the window rejoins the same conversation.
- **No-root guard:** if `rootFolderStore.rootURL == nil`, the toolbar/menu "AI"
  actions and every right-click "Ask AI…" are disabled (or route to the
  folder-chooser). No root → no root session.

---

## B) The right-click "Ask AI…" action + the adopt / fix flow

### One mechanism, three entry points, two behaviors

All three entry points — **right-click "Ask AI…"** (any row), the sidebar
**"Bring under AI Control"** (untouched), the sidebar **"Let AI fix it"**
(invalid nested) — do the same two things: **(1) open/raise the AI window, and
(2) hand the folder to the root session.** They differ only in *what text* gets
handed, and that splits by row kind into two behaviors:

| Row kind | Behavior | What's sent |
|---|---|---|
| **untouched** | **Directed — auto-send** | `RoutinePromptKind.adopt` text + a path appendix |
| **invalidNestedOrganizer** | **Directed — auto-send** | adopt text + a "fix the nesting" appendix |
| **project / organizer** | **General — pre-fill (unsubmitted)** | a short editable reference line |

This is exactly the generalization the wiki already predicted: *"model these as
`(folderURL, promptKind)` sent to the dashboard AI session, and route the
right-click menu's AI action through the same path — don't invent per-action
plumbing."* The two interim `revealInFinder` closures in `DashboardView` finally
**split** into their real targets, as that lesson anticipated.

### "Hand the path as a reference," concretely

**Directed (untouched / invalid) → auto-send, mirroring `rebuildClaudeMd`.**
The stored prompt is long and report-first, so auto-sending is both safe and
proven. New store method, parallel to `rebuildClaudeMd(for:appendix:)`:

```
adopt(folderURL:)  // and fixNesting(folderURL:) — see deferred note
```

It resolves the root session via `aiWindowSession(rootURL:)`, composes
`promptText(for: .adopt)` **+ the path appendix**, and sends it:

- **Fresh session** → send on `session.onReady` (the same trick
  `authorModules` uses, so the prompt isn't fired into a still-booting TUI).
- **Existing session** → `session.sendLine(prompt)` after the ~0.9 s settle beat
  (the same delay `rebuildClaudeMd` uses).

Both use the **paste-safe `sendLine`** (type, then a lone `\r` ~0.25 s later) —
mandatory for any programmatic input to Claude's TUI (the standing paste-detection
lesson).

**Path appendix microcopy** (appended beneath the stored prompt — the
`RoutinePromptKind` convention "the app appends context beneath the stored
prompt"):

```
<adopt prompt text>

The folder to analyze is: /dev/code/my-app
```

For **invalid nested organizer**, the appendix instead names the problem and the
two allowed fixes (straight from `InvalidNestedDetail`'s copy):

```
<adopt prompt text>

This folder is an organizer (.organize) nested inside another organizer,
which isn't allowed. Fix it by either moving it out to the root, or moving
its projects up into the parent organizer and removing its .organize marker.
The folder is: /dev/organizer/nested-organizer
```

**General (project / organizer) → pre-fill, unsubmitted.**
Here we don't know the user's question, so we don't auto-send. New store method
`askAI(about folderURL:)`: resolve the root session, then **`session.send(...)`
*without* a trailing `\r`** — this types the text into Claude's input box and
leaves the cursor there for the user to edit or extend, then press Enter
themselves. Pre-fill text:

```
Tell me about the folder at /dev/code/my-app.
```

The user can send it as-is (one keystroke) or replace it with their real
question. This is the literal "hand the path as a reference" from §8.4.

> **Live-test flag (honesty, per the wiki):** typing an un-submitted line via
> `send()` relies on Claude's TUI showing it as *editable inline text*, not
> collapsing it into a "pasted N lines" pill. `sendLine` deliberately splits the
> `\r` off for the opposite reason, so pre-fill-without-submit is plausible but
> **unverified against the current `claude` TUI.** If it renders as a paste pill
> or otherwise isn't editable, fall back to **auto-sending** the short reference
> line via `sendLine` (the AI then acknowledges the folder and the user replies).
> Decide this by driving the real TUI — live testing overrides this spec.

### Every action updates the reference chip + raises the window

Regardless of behavior, each action also sets an `@Published var aiReference`
(folder name + path) on the store, which the window header chip renders, and the
view layer calls `openWindow(id: AIWindow.windowID)`. So the feedback is always:
**window comes forward + chip shows the folder + (directed) the prompt starts
streaming / (general) the line appears in the input.** No silent actions.

### The verdict → confirm → apply conversation

The `RoutinePromptKind.adopt` default text **already frames this correctly** —
no new prompt design needed:

> *"Analyze this folder against STRUCTURE.md and decide whether it is a project
> or an organizer. Report your verdict and the changes you'd make before
> touching anything. If I agree, bring it under AI Control…"*

So the framed flow for an untouched folder is:

1. User right-clicks the untouched row → **"Ask AI…"** (or clicks the sidebar
   **"Bring under AI Control"**). AI window raises; chip shows the folder; the
   adopt prompt + path auto-sends.
2. **AI reports its verdict in the terminal** — e.g. *"This looks like a project.
   I'd add `.project`, generate `CLAUDE.md` from the global modules, and create
   `updates/`, `issues.txt`, `.gitignore`, `.env`. Proceed?"*
3. **User answers in the CLI** ("yes" / "go for it") — a real Claude turn typed
   by the user. The app does **not** mediate this confirm step (principle 2); the
   report-first prompt is what guarantees nothing changes without the "yes."
4. **AI applies the changes** via the CLI.
5. **Dashboard reflects it:** the row flips from *untouched* → *project* (or
   *organizer*) once the markers exist on disk. See "keeping the dashboard in
   sync" below.

Same shape for the invalid nested organizer, ending with the folder no longer
classified as `invalidNestedOrganizer`.

### Wiring the sidebar buttons to the AI window (replacing the Finder interim)

`ProjectSidebarView` keeps both buttons and their positions; only the closures
and captions change.

- **Untouched — `UntouchedDetail`:**
  - Button label unchanged: **"Bring under AI Control"**.
  - `onBringUnderControl` in `DashboardView` stops calling `revealInFinder` and
    instead calls `sessionStore.adopt(folderURL: node.url)` + `openWindow(id:)`.
  - New caption (replacing the "reveals the folder in Finder" interim note):
    *"Sends the folder to the AI window; it reports what it is and what it'd
    change before touching anything."*
- **Invalid nested — `InvalidNestedDetail`:**
  - Button label unchanged: **"Let AI fix it"**.
  - `onLetAIFix` calls `sessionStore.fixNesting(folderURL: node.url)` (or the
    adopt+fix-appendix fallback) + `openWindow(id:)`.
  - New caption: *"Sends the folder to the AI window with a fix prompt; it
    proposes the fix and applies it if you agree."*

The two closures — today both pointed at one `revealInFinder` — become **two
distinct closures**, exactly as the wiki's *"when the AI window lands, split them
to send their respective predefined prompts"* note prescribed.

### Wiring `RowRightClick` (the universal "Ask AI…" item)

Today `RowRightClick` pops a menu **only when `isRunning`** (Stop / Force Close).
Change it to **always** pop a menu:

- **Always present:** **"Ask AI…"** — fires a new `onAskAI` closure.
  - The label is uniform across all row kinds (fulfilling §8.4's single "AI"
    concept and the "selection/actions mean the same everywhere" lesson), but
    the closure's *behavior* is kind-aware: untouched/invalid → directed
    adopt/fix (this is how §9.3's "the way to get an AI verdict on an untouched
    folder" is delivered from the right-click); project/organizer → general
    pre-fill. `DashboardView` branches on `row.node.kind` when routing `onAskAI`
    into the store.
- **Appended only when `isRunning`:** the existing **Stop** and **Force Close**
  items, unchanged.
- `hitTest` still claims only right-mouse events; drop the `guard isRunning else
  { return }` early-out so the menu builds for every row (with the running-only
  items conditionally added). `onSelect` still selects the row first.

So an untouched folder now has **two** paths to a verdict (both landing in the AI
window): the sidebar's **"Bring under AI Control"** and the right-click
**"Ask AI…"** — matching §9.3 verbatim ("The sidebar offers to bring it under AI
Control, or I use the right-click AI option").

### Keeping the dashboard in sync after an apply

After the AI writes `.project` / `.organize`, the dashboard must rescan for the
row to reclassify. Reuse the **Rebuild completion pattern**: track the adopt/fix
like `RebuildState` (see it go `working` → `awaitingInput`), and on completion
have `DashboardView` re-run `viewModel.rescan()` — an exact parallel to the
existing `.onChange(of: sessionStore.rebuildingURLs)` handler. This makes the row
flip without the user having to do anything.

- **MVP fallback if that's too much for a first cut:** rely on the *existing*
  rescan-on-activate (`scenePhase == .active` already calls `rescan()`), so the
  row updates when the user returns to the dashboard. Acceptable, just not live.
  Prefer the completion-tracking version — the plumbing is a copy of
  `advanceRebuild`.

---

## MVP vs deferred

### MVP
- **AI window as a `Window` scene** (`AIWindow`, `windowID`), reusing the Global
  Config multi-scene store injection + `TerminalContainerView` + the
  `DraftModulesSheet` header/terminal chrome (extracted into a shared view).
- **Root session** via new `aiWindowSession(rootURL:)`, added to
  `globalSessionURLs` (no pin / notification / badge — resolves the wiki's
  flagged rough edge).
- **Open/raise from:** dashboard toolbar **"AI"** button, a **`CommandMenu("AI")`**
  menu-bar entry, and automatically from every AI action.
- **`RowRightClick` always shows a menu**; **"Ask AI…"** on every row; Stop /
  Force Close still appended only when running.
- **Directed adopt (untouched)** auto-sends `RoutinePromptKind.adopt` + path
  appendix via `adopt(folderURL:)` (onReady on fresh, `sendLine` on existing).
- **Sidebar buttons rewired** off `revealInFinder` to the store actions + window
  open, with updated captions. The two closures split.
- **General "Ask AI…"** on project/organizer pre-fills the reference line
  (`session.send`, unsubmitted).
- **Reference chip** in the AI window header for visible feedback; `aiReference`
  published by the store.
- **Dashboard reclassifies** after apply (completion-tracking rescan; or, at
  minimum, the existing rescan-on-activate).

### Deferred
- **Verify pre-fill-without-submit** against the live TUI; adopt the
  auto-send-the-reference-line fallback if it doesn't render as editable text.
  (Live-test item — the standing "live testing overrides spec" lesson.)
- **A dedicated `fixNestedOrganizer` `RoutinePromptKind`** (with default text +
  Settings entry + seeding). MVP reuses `.adopt` with a fix appendix; promote it
  to its own editable routine prompt later if the fix framing needs tuning.
- **Reference history / multiple chips** (the window currently shows only the
  latest reference; the conversation itself retains context).
- **Clearing/"new conversation"** control beyond the chip's `✕`.
- **Root session token usage / activity surfacing** for the AI window (ties into
  the Phase-10 session-log work; keep it out until that data is real, per the
  honesty rule — no faked status).
- **A dashboard-embedded panel** variant, if a separate window ever feels heavy
  in real use (revisit only on live feedback).

---

## Components / patterns referenced (build on these, don't reinvent)

- **`DraftModulesSheet`** (`GlobalConfigWindow.swift`) — the terminal-in-a-panel
  seed; its header + `TerminalContainerView` chrome is the AI window's body.
- **Global Config `Window` scene + App-scope `@StateObject` injection**
  (`AIControlApp.swift`) — the multi-scene pattern the AI window copies.
- **`TerminalSessionStore.authorModules(at:)` / `globalSessionURLs`** — the
  template for `aiWindowSession(rootURL:)` and the notification-exclusion.
- **`TerminalSessionStore.rebuildClaudeMd(for:appendix:)`** — the template for
  `adopt(folderURL:)` (auto-send stored prompt + appendix, onReady/sendLine).
- **`TerminalSession.onReady` / `sendLine` / `send`** — ready-timing, paste-safe
  submit, and unsubmitted pre-fill respectively.
- **`RoutinePromptKind.adopt`** — the report-first verdict→confirm→apply prompt;
  used as-is with a path appendix.
- **`RowRightClick`** — extend to always show a menu with **"Ask AI…"**.
- **`ProjectSidebarView` (`UntouchedDetail`, `InvalidNestedDetail`)** — rewire
  the two buttons off `revealInFinder`; update captions.
- **`SidebarHeader`, `MonospaceChips`/chip styling, `EmptyStateView`** — reuse
  for the AI window header, reference chip, and empty state so it looks native.
