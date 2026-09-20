# UX notes — The Global Config control window: navigation & integration

Design pass. No code. Hand to engineer. **Scope = structure, menus, window
integration, MVP staging.** A separate note covers content authoring and the
in-app editing model — this note deliberately stops at "Reveal / Open in editor"
and does not specify editing internals.

Reuses the existing minimalist vocabulary: `SidebarSection`, `SidebarKeyValue`
(with its `placeholder` flag), `MonospaceChips`, `SidebarHeader`,
`EmptyStateView`, `GlobalConfigBanner`. Respects the two standing constraints
from the Phase 6 pass: **honesty** (never fake a status; deferred data is a
dim `— …` placeholder, never an invented green/red or a dead button) and
**`attentionRed` is awaiting-input only** (nothing here is an alarm).

The driving problem, verbatim intent: the user clicked "Create global config",
it silently made `~/.ai-control/` and vanished, and they were confused. They
want a real place — "a window like on the top bar, open something like View →
Settings" — to see and control the `.md` files and prompts. MVP they'll accept:
"just so that I can open the folder where it is and I'll edit it inside there."

---

## 1. Menu-bar & window integration

### Recommendation: one dedicated **Global Config** window, opened from the app menu at ⌘, and from a dashboard toolbar button. No "View" menu.

Reasoning, and a gentle correction of the "View → Settings" idea:

- **The app menu, not View.** On macOS a **View** menu is reserved for changing
  how the current content is *displayed* (show/hide panes, zoom). Opening a
  configuration surface belongs in the **app menu** as **Settings…** with the
  system shortcut **⌘,**. That is the muscle-memory location every Mac user
  already knows, and it is exactly what the user is reaching for when they say
  "something like Settings." We honor the intent, place it correctly.

- **A real `Window`, not the SwiftUI `Settings` scene.** The stock `Settings`
  scene gives a small, fixed, non-resizable prefs panel that stays out of the
  Window menu. Our config surface must **scale as files grow** (modules, wiki
  pages, secrets, prompts) and wants a resizable split layout. So model it as a
  first-class `Window("Global Config", id: "global-config")` and wire ⌘, to
  *open that window* rather than the built-in Settings scene. It reads as
  "Settings" to the user but behaves like the control panel it is.

- **The app currently has no custom menus at all** (`AIControlApp.swift` is a
  bare `WindowGroup { DashboardView() }`). We add the minimum.

**Exact scene + commands to add (structure, not code):**

- New scene: `Window("Global Config", id: "global-config")` presenting
  `GlobalConfigWindow` (the new root view specced below). Single instance —
  reopening the command re-focuses the existing window.
- `.commands { … }` on the `WindowGroup`:
  - `CommandGroup(replacing: .appSettings)` → one button **"Settings…"**,
    shortcut **⌘,**, action `openWindow(id: "global-config")`. This puts our
    item at the standard app-menu spot and claims ⌘,.
  - `CommandGroup(after: .windowList)` → **"Global Config"** (no shortcut), same
    action, so the window is reopenable from the Window menu after it's closed.
    This is the closest honest answer to the user's "on the top bar" ask.

**Discoverable entry point on the dashboard (most important for a first-timer):**
add a **gear toolbar button** to the dashboard's existing `.toolbar` (next to
the current "Choose Folder…" item), SF Symbol `gearshape`, label/tooltip
**"Global Config"**, same `openWindow` action. A visible control beats a
shortcut for someone who doesn't yet know the concept exists. This satisfies
PROJECT.md §8.1's "entry points to the Secrets/Settings window."

**Net menu additions:** App menu → **Settings… ⌘,**; Window menu → **Global
Config**; dashboard toolbar → gear button. Nothing else. No new top-level menu.

**Consolidation call (§8.5 vs §8.6):** PROJECT.md imagines a *separate* Secrets
window and Settings window. For "minimalistic: only what we truly need," fold
both into this **one** Global Config window as two sections (Secrets, Prompts).
`~/.ai-control/` is a single thing; controlling it from one window is simpler,
more discoverable, and less chrome. Flagged for the user's live-test call — if
Secrets later grows heavy it can be promoted back to its own window, but it
should not ship as a second window on day one.

---

## 2. Information architecture of the window

### Layout: `NavigationSplitView` — a section list on the left, a detail pane on the right.

This is the modern System-Settings shape and it **scales**: adding a wiki page
or a module never reflows a fixed tab bar; the left list just grows a count.
Top-mounted `TabView` tabs would cramp as content grows — avoid them.

**Left column — section list (fixed order, top to bottom):**

| Section | SF Symbol | What it controls |
|---|---|---|
| **Overview** | `shippingbox` | Global-config state, create/reveal, the README, what this whole thing *is*. |
| **Modules** | `doc.text` | `modules/*.md` — the files merged into each CLAUDE.md. |
| **Wiki** | `book` | `wiki/*.md` knowledge pages + their usage descriptions. |
| **Prompts** | `text.bubble` | The 6 routine prompts (`RoutinePromptKind`). |
| **Secrets** | `key` | Key **names** from `.env` (never values). |
| **General** | `folder` | Root folder connection (§8.6) + config repo location. |

Window frame: `minWidth 640, minHeight 420, idealWidth 760`. Left list
`minWidth 180`. Detail pane scrolls.

**Reuse the sidebar vocabulary inside the detail pane** so the window looks like
the rest of the app: each detail screen is a `ScrollView` of `SidebarSection`
blocks; status lines are `SidebarKeyValue` (with `placeholder: true` for
genuinely-uncomputable data); module/wiki/secret name lists are `MonospaceChips`;
the header of each screen reuses the `SidebarHeader` idiom (glyph + title + one
caption line). No new component vocabulary is introduced. The one small new
reusable piece: a **section-launcher row** — a right-aligned pair of small
`.bordered` buttons `[Reveal in Finder] [Open in editor]` — used identically on
every file-backed section. Build it once as `ConfigFolderActions(folderURL:,
fileURL:?)` and reuse.

**Per-section detail content:**

**Overview** — the home screen and the discoverability anchor.
- `SidebarHeader`: glyph `shippingbox`, title **"Global config"**, caption =
  the resolved path `~/.ai-control` (tertiary).
- One plain sentence (the discoverability one-liner, see §5).
- `SidebarSection "STATUS"` with a single `SidebarKeyValue` keyed
  **`Global config`** carrying the honest state (values in §4).
- The **Create global config** button (absent state only) — see §4.
- `ConfigFolderActions` for the repo root: `[Reveal in Finder]` and
  `[Open README]` (opens `README.md`, which already explains the layout).
- Once set up, a `SidebarSection "CONTENTS"` summarizing counts as quiet
  `SidebarKeyValue` rows: `Modules · {n}`, `Wiki pages · {n}`, `Prompts ·
  {n} ({e} edited)`, `Secrets · {n}`. These double as a table of contents and
  make the whole config legible at a glance.

**Modules**
- Header + one caption: **"Modules are merged into each project's CLAUDE.md.
  Authored by the AI, not by the app."**
- If `config.modules` empty → `EmptyStateView` (systemImage `doc.text`, title
  **"No modules authored yet"**, message **"Modules are written by the AI in a
  later phase. The folder is ready for them."**).
- Else → `MonospaceChips` of module names, plus per-module `SidebarKeyValue`
  `{Name} · changed {relative}` (reusing `SidebarFormat.relativeString` over
  `GlobalModule.modifiedAt`). These mtimes are exactly what drift compares.
- `ConfigFolderActions(folderURL: modules/)`.

**Wiki**
- Header + caption: **"Knowledge pages the AI reads and writes. Each starts with
  a one-line usage description."**
- Empty → `EmptyStateView` title **"No wiki pages yet"**.
- Else → one row per page: page name + its `usageDescription` as the secondary
  value (`SidebarKeyValue`), so pages are self-describing. `ConfigFolderActions`
  per page (Open in editor) and for the `wiki/` folder.

**Prompts** — the section most ready for real MVP control (the text already
exists on disk / as defaults).
- Header + caption: **"The prompts the app's buttons send to Claude. Edit these
  to change what each routine does."**
- One row per `RoutinePromptKind.allCases`, ordered as declared. Each row:
  `kind.title` (e.g. "Stop and save routine") + a **Default / Edited** badge
  (see §3 for how state is computed) + `[Open in editor]` opening
  `prompts/<key>.md`.
- `ConfigFolderActions(folderURL: prompts/)` at the bottom.

**Secrets**
- Header + caption: **"Global secrets shared with projects. Names shown here;
  values live only in `.env`."**
- `MonospaceChips` of `config.secretNames` (names only — honest, matches §6.5).
- Empty → `EmptyStateView` title **"No secrets yet"**, message **"Add keys to
  `.env` as `KEY=value`, one per line."**
- `ConfigFolderActions(fileURL: .env)` → `[Reveal in Finder] [Open in editor]`.
- Explicit deferral note in tertiary caption: **"In-app add/edit coming later."**

**General**
- `SidebarSection "ROOT FOLDER"`: `SidebarKeyValue` `Root · {path or "— not
  connected"}` (placeholder when nil) + **`Change…`** button reusing the
  dashboard's existing `fileImporter` path into `viewModel.chooseRootFolder`.
- `SidebarSection "CONFIG REPO"`: `SidebarKeyValue` `Location · ~/.ai-control`
  + `[Reveal in Finder]`.

---

## 3. Honest state display (config exists? modules authored? prompts edited?)

Reuse the exact state language from the Phase 6 note so the window, the
dashboard strip, and the per-project drift row all say the same thing.

- **Config existence** (Overview `Global config` line) — three states, §4 table.
- **Modules authored** — the count + empty state carry it. Never claim "ready"
  when `modules/` is empty; the Overview status line says **"Skeleton created ·
  no modules authored yet"** in that middle state.
- **Prompt default vs edited** — compute per kind: read the stored file text via
  `config.prompt(kind.key)`. Badge is **"Edited"** when a stored file exists and
  its trimmed text differs from `kind.defaultText`; otherwise **"Default"**.
  (Because the app falls back to defaults when a file is missing, "no file" and
  "file equals default" both read as **Default** — which is the truth the user
  cares about: is this prompt still the built-in behavior?) Badge is a quiet
  tertiary text tag, not a colored pill — meaning by word, per the color rule.
  Overview's `Prompts · {n} ({e} edited)` summarizes the same fact.

No green/red anywhere in this window. State is carried by words, counts, and the
presence/absence of the Create button — identical to the Phase 6 discipline.

---

## 4. MVP staging — crisp line between what ships now and what's deferred

### MVP (ships now): a real, honest **launcher + status** window.

The user explicitly accepts "just open the folder and I'll edit inside there."
The MVP delivers exactly that, but framed as genuine control rather than a
placeholder:

**Ships:**
1. The **Global Config window** with all six sections and the split layout above.
2. Every file-backed section shows its **live contents read from disk**
   (module names + mtimes, wiki pages + descriptions, the 6 prompts with
   Default/Edited badges, secret names) — this is real, honest visibility, not a
   stub.
3. **`[Reveal in Finder]`** and **`[Open in editor]`** on every section and on
   individual files. `Reveal` = `NSWorkspace.shared.activateFileViewerSelecting`;
   `Open in editor` = `NSWorkspace.shared.open(fileURL)` (opens `.md` in the
   user's default Markdown/text app). Reveal is the primary, always-safe action;
   Open in editor is the convenience. This *is* "open the folder where it is and
   edit inside there" — promoted to a per-section, one-click affordance.
4. **Create global config** lives here (Overview) with visible result — see §5.
5. **Honest status** everywhere (config exists / modules authored / prompt
   edited / root connected) per §3.
6. **Live refresh:** the window calls `globalConfig.reload()` on
   `.onAppear` and when the window becomes key (`scenePhase`/`controlActiveState`),
   so edits made in Finder/Xcode reflect back without relaunch. Same reload the
   dashboard already does on `scenePhase == .active`.

**Explicitly deferred (later, "fuller in-app editing" version):**
- In-window text editing of prompts and `.env` (a `TextEditor` per prompt, a
  key/value secrets table with mask/reveal per §8.5). Until then, Open-in-editor
  covers it honestly.
- AI-driven module/wiki authoring (belongs to the AI-window phase; the window
  only *reveals* those folders now).
- Any diff/restore-to-default for prompts.

The MVP feels like control because: it is a **named window** you open
deliberately, it **shows the true contents** of every part of the config, and
each part has a **one-click way to edit it** — the exact thing the user asked
for, with nothing faked.

---

## 5. Fixing the silent-button problem + discoverability

### The silent create → give creation a home with a visible, persistent result.

Root cause: Create ran on the dashboard strip and the strip vanished, so the
result was invisible. Fix both the trigger and the feedback:

- **Move the authoritative Create action into the Overview section**, where the
  window stays open and the result is right there: on click, `createSkeleton()`
  runs, the `Global config` status line **changes in place** from `— not set
  up` to `Skeleton created · no modules authored yet`, the Create button is
  replaced by the `[Reveal in Finder] [Open README]` actions, the CONTENTS
  summary appears, and a **transient confirmation caption** shows for a few
  seconds beneath the status line:
  > **Created `~/.ai-control/` (skeleton).** Modules aren't authored yet — that
  > happens with the AI in a later phase.

  (Same copy as the Phase 6 note, now shown *in the window that stays open*.)

- **Re-point the dashboard strip.** Keep `GlobalConfigBanner` (it's the one
  proactive nudge while config is absent), but change its button so clicking it
  is never a dead-end:
  - Button label → **"Set up…"** (was "Create global config").
  - Action → `openWindow(id: "global-config")` **instead of** silently creating.
    The user lands on Overview, reads the one-liner, and clicks Create *there*,
    where they see it happen. The strip still auto-disappears once the skeleton
    exists (unchanged behavior), but now clicking it *opens something* rather
    than making a folder vanish. This directly answers "it disappeared and
    confused me."
  - (If we want to preserve one-click create from the strip, the acceptable
    variant is: create on click, then the strip morphs in place into a
    confirmation line + **"Open Global Config"** button before dismissing —
    never disappear on a bare success. Recommended primary is "Set up…" →
    window, because the window is where every follow-up action lives.)

- **Every subsequent action gives feedback.** Reveal flashes Finder to front
  (OS feedback). Open-in-editor launches the editor (OS feedback). Create shows
  the transient caption above. Change-root updates the `Root ·` line in place.
  No action in this window completes invisibly.

### Discoverability: from "I don't know what this is" to controlling it.

1. **Two persistent entry points** (toolbar gear + Settings ⌘,) mean the concept
   is always reachable, not just surfaced by a one-time strip.
2. **The absent-state strip** explains the concept in one line before anything
   exists: *"Global config isn't set up. Projects share coding principles,
   workflow rules and secrets from `~/.ai-control/`."* (already in
   `GlobalConfigBanner`) — keep verbatim.
3. **Overview one-liner** (always present, the plain-language definition):
   > **This is the shared brain every project inherits.** Coding principles,
   > workflow rules, knowledge pages, routine prompts and secrets live in
   > `~/.ai-control/` and are reused across all your projects.
4. **Empty states teach, not scold.** Each empty section states what the folder
   is *for* and who fills it (the AI vs. you), so an empty Modules screen reads
   as "waiting for the AI," not "broken."
5. **Surface the README** (Open README on Overview) — it already documents the
   folder layout; make it one click.

---

## Open calls for the engineer

1. **One window vs. §8.5's separate Secrets window** — recommend one window,
   Secrets as a section. Flag for the user's live-test reaction (this project
   favors reacting to a real build over spec).
2. **⌘, via `CommandGroup(replacing: .appSettings)` opening a `Window`** rather
   than adopting the SwiftUI `Settings` scene — confirm; it's what lets the
   window be resizable and Window-menu-reopenable while keeping the idiom.
3. **`GlobalConfigStore` is currently owned by `DashboardView`.** The new window
   is a separate scene and needs the same store. Lift `GlobalConfigStore` (and
   `RootFolderStore`, for the General section's Change-root) to app scope and
   inject into both scenes, or use a shared `@Observable` singleton. Confirm the
   sharing approach so both surfaces reload in lockstep.
4. **`Open in editor` default app** — `.md` may open in Preview/Xcode/VS Code
   depending on the user's Finder association; that's acceptable and honest for
   MVP. Reveal in Finder is the guaranteed-useful fallback and stays primary.
5. **Create ownership** — Create still calls the existing
   `GlobalConfigStore.createSkeleton()` (app scaffolds empty structure only;
   principle 2 intact). No change to what it writes, only *where the button
   lives* and *how the result is shown*.
6. **`ConfigFolderActions`** is the only new reusable component; keep it as low-
   chrome as `SidebarKeyValue` (small `.bordered` buttons, trailing-aligned).
