# UX notes — The New Project flow (§9.2)

Design pass. No code. Hand to engineer. **Scope = the New Project entry point,
the create form, what the app vs. the AI each do on submit, the feedback loop,
and the edge cases.** Written to match the standing INIT discipline:

- **Honesty** — never fake a status; deferred/uncomputable data is a dim `— …`
  placeholder, never an invented green/red or a dead button.
- **`attentionRed` is awaiting-input only.** Nothing here is an alarm; warnings
  are quiet secondary/tertiary text.
- **Every action gives visible feedback** — a silent action reads as "nothing
  happened" (the exact bug the Global-Config strip hit).
- **Live testing overrides this spec.** Build it, react to the real thing.

Reuses the existing vocabulary: `EmptyStateView`, `SidebarSection`, the
dashboard `.toolbar`, `ProjectView` (full-window session view),
`TerminalSessionStore.session(for:)` + `onReady` + `sendLine` (the paste-safe
send proven in Phase 5), the `RoutinePromptKind.newProject` prompt (default text
already exists), and the `appendix` pattern from `rebuildClaudeMd(for:appendix:)`
(base prompt + "\n\n" + form input).

**The one hard principle to hold (principle 2): the app never authors project
files.** The AI writes `.project`, `CLAUDE.md`, `.gitignore`, `.env`, `updates/`,
`issues.txt`, the GitHub repo and the first commit. See §3 for the single
minimal act the app *is* allowed (create the empty target directory), and why
that is consistent with the Phase-6 `createSkeleton()` precedent.

---

## 1. Entry point

### Recommendation: a primary **New Project** toolbar button, plus a prominent action in the "empty folder" empty state. Both route to the same sheet.

**Toolbar (primary, always-visible entry).** The dashboard `.toolbar` today has
only `Button("Choose Folder…")`. Add a leading `ToolbarItem`:

- Label: **New Project**
- SF Symbol: `plus` (a `Label("New Project", systemImage: "plus")`), shown with
  title + icon so it's unmistakable.
- Placement: **leading / primaryAction** — it is the app's main creative act and
  §8.1 explicitly calls for it, so it sits first, before the gear (Global Config,
  per `ux-notes-config-window.md`) and the existing "Choose Folder…".
- Enabled only when a root folder is connected (see §5). When disabled, a
  tooltip: **"Connect a root folder first."**

Resulting toolbar order: **[ + New Project ] [ ⚙ Global Config ] [ Choose
Folder… ]  …  🔎 Search**.

**Empty-state (discoverability for a fresh, empty root).** The "root connected
but empty" `EmptyStateView` currently reads title *"This folder is empty"* /
message *"Add a project folder to get started."* with **no action**. Give it the
real action:

- `actionTitle: "New Project"`, `action:` → open the sheet.
- Keep the `tray` glyph and title; change the message to **"Create your first
  project, or add folders to this location outside the app."**

This turns the dead-end empty state into the obvious first step, and matches
`EmptyStateView`'s existing `actionTitle`/`action` affordance (already used for
"Choose Folder").

Not in the "no matches" search empty state and not in the "no root" empty state
(there, "Choose Folder" stays the single call to action).

---

## 2. The form

### Layout: a **sheet** on the dashboard window (`.sheet`), not a separate window.

A create form is modal, short-lived, and focused — a sheet is the platform-right
shape (same reasoning macOS uses for "New Document" style dialogs). A separate
`Window` is reserved for the persistent Global Config control surface; this is a
one-shot form. The sheet is presented from `DashboardView` via a
`@State private var isCreatingProject = false` gate, mirroring how
`isChoosingFolder` drives the `fileImporter`.

**Frame:** `minWidth 460, idealWidth 520`, height fits content (the description
editor gets a fixed `minHeight`). Uses a SwiftUI `Form` so fields align and it
reads like native Settings.

**Title:** sheet header **"New Project"** (`.font(.title2.weight(.semibold))`),
one tertiary caption line beneath: **"The AI sets it up under AI Control and
makes the first commit."** (sets the mental model — the app hands off to Claude).

### Fields (top to bottom)

**1. Name** — `TextField`, label **"Name"**, placeholder **"my-project"**.
- Monospaced field text (it becomes a folder name and likely the repo name).
- Live-validated (rules in the validation block). On invalid, a tertiary red-free
  caption appears *beneath the field* in secondary text: e.g. **"A folder named
  "my-project" already exists here."** (No alarm color — it's guidance, and per
  the color rule meaning is carried by words.)

**2. Location** — a `Picker` (menu style), label **"Location"**.
- Options, in this order:
  - **Root** — shown as the root folder's `lastPathComponent` with a `folder`
    glyph, e.g. **"dev (root)"**.
  - Each **organizer** found in the scan (`viewModel` nodes where
    `kind == .organizer`), by name, with the `folder` (organizer) glyph, e.g.
    **"clients"**.
- **Default: Root.**
- Only root + organizers are valid targets (§3.1/§3.3: a project sits in the root
  or in an organizer; **no nested organizers**, and never inside another
  project). Invalid nested organizers and existing projects are **not** listed.
- If there are no organizers, the picker still shows the single Root option (not
  hidden) so the field is always present and the model is clear.

**3. Visibility** — a segmented `Picker`, label **"Visibility"**, options
**Private** / **Public**.
- **Default: Private** — the global repo and the privacy-first posture in §6.5
  make Private the safe default; Public is a deliberate choice.
- One tertiary caption beneath: **"Creates a Private / Public GitHub repo."**
  (text updates with the selection).

**4. Description** — a multiline `TextEditor`, label **"What do you want to
build?"** (this is the required INIT description, §5.5 / §9.2).
- `minHeight ≈ 120`, monospaced-off, scrolls when long.
- Helper caption above the editor (tertiary): **"Describe the project in detail —
  this becomes the INIT update and guides the whole setup. The more specific,
  the better."**
- Required; empty is invalid (see validation).

### Buttons

- Primary: **Create Project** (`.borderedProminent`), bottom-trailing, is the
  sheet's `.defaultAction`. **Disabled until the form is valid.**
- Secondary: **Cancel** (`.cancel` role, Esc), bottom-leading. Closes the sheet,
  discards input.

### Validation (all live; primary button disabled unless all pass)

| Field | Rule | Message shown when it fails |
|---|---|---|
| Name | Non-empty after trim | *(button just stays disabled; no scolding on an untouched empty field)* |
| Name | Valid folder name — no `/`, no `:`, doesn't start with `.`, not `.`/`..`, within a sane length | **"Use a folder-safe name (no slashes, not starting with a dot)."** |
| Name | **Not already taken at the chosen Location** — case-insensitively compare against existing entries in the target directory (a fresh `FileManager` check of the target dir at validation time, not only the cached scan, so a folder created outside the app is still caught) | **"A folder named "{name}" already exists here."** |
| Description | Non-empty after trim | *(button stays disabled; optional tertiary hint "Add a description to continue" once the field has been touched)* |

Name validation re-runs when **Location** changes (the same name can be free in
one organizer and taken in another).

---

## 3. What happens on submit — the app/AI division

### The clean split (keeps principle 2 intact)

**The APP does exactly two things, both mechanical, neither authoring content:**

1. **Creates the empty target directory** at `<location>/<name>` (a bare
   `mkdir` — an empty folder, nothing inside it). This is the minimal act needed
   so Claude has a real cwd keyed to the project's own URL. It is consistent with
   the Phase-6 precedent recorded in `wiki.md`: *"The app scaffolds the config
   skeleton, but never authors module content… laying down empty structure is
   not forbidden; authoring content is."* An empty directory contains no project
   files and no content — the AI still writes every file.

2. **Opens a Claude session in that directory and sends the prompt.** Reuse
   `TerminalSessionStore.session(for: newDir)` (starts `claude` under the app's
   hooks + `--dangerously-skip-permissions`, keyed to the new project URL — so
   running/awaiting tracking, Stop, etc. all work immediately). Then, **only once
   the fresh session signals `onReady`** (Phase-5 lesson: a fixed delay races a
   cold session's boot), send via the paste-safe `sendLine`:

   `newProject` base prompt (`globalConfig.promptText(for: .newProject)`, falling
   back to the built-in default) **+ "\n\n" + an appended parameter block** (the
   same base+appendix shape as `rebuildClaudeMd(for:appendix:)`).

**The APPENDED block (exact format):**

```
Project name: <name>
Location: <absolute path of the chosen root/organizer>
Visibility: <private|public>

INIT description:
<the multiline description, verbatim>
```

**The AI does everything else** (§9.2, and already spelled out in the
`newProject` default prompt): selects relevant global modules and compiles
`CLAUDE.md`; creates `.project`, `.gitignore` (covering `.env`), `.env` with the
secrets this project needs, `updates/`, `issues.txt`; creates the first **INIT**
update from the description; creates the GitHub repo with the chosen visibility,
connects it, and makes the first commit.

### Why not "open the session at the parent and let the AI `mkdir`"?

Because the session, the running/awaiting status keying, Stop, and the
full-window `ProjectView` are all keyed on **one URL**. If the app opened the
session at the organizer/root and the AI created a subfolder, the terminal's cwd
and the tracked URL would be the parent, not the project — the new project would
never get its own keyed session or its own dashboard row session state. Creating
the empty dir first and keying the session to it is both simpler and correct.

### New store entry point (recommended API)

Add to `TerminalSessionStore`, mirroring `authorModules(at:)`:

`func startNewProject(at newDir: URL, visibility: Visibility, initDescription: String, name: String) -> TerminalSession`

- Creates `newDir` (empty) if absent.
- `let isNew = sessions[newDir] == nil`; `session(for: newDir)`.
- If `isNew`, sets `session.onReady = { session.sendLine(base + "\n\n" + appended) }`.
- Returns the session so the view can present it full-window.

(Directory creation is the one file-system write; it writes **no file contents**,
so principle 2 holds. If we later want even the `mkdir` out of the app, the AI
prompt would have to be sent to a session rooted elsewhere — rejected above for
the keying reason.)

---

## 4. Feedback & result

### On submit: open the project's session full-window immediately (reuse `ProjectView`).

No silent action. The instant the sheet's **Create Project** is pressed:

1. Sheet dismisses.
2. The app creates the empty dir + starts the session (via `startNewProject`).
3. `DashboardView` sets its existing `openProject` state to a
   **synthetic `OpenProject`** for the new folder, so `ProjectView` fills the
   window and the user **watches the AI build the project live** in the embedded
   terminal — the same view used for double-click and for watching a Rebuild.

**Constructing the synthetic node:** `openProject` needs an `AIControlNode`, but
the `.project` marker doesn't exist yet, so the scan hasn't classified it.
Construct a lightweight display node: `AIControlNode(url: newDir, kind: .project,
lastActivityDate: .now)`. `ProjectView` only uses `node.name` (folder name) and
`node.url` for its header, so a synthetic node renders correctly; the real
scanned node replaces it on the next rescan. (Alternatively give `OpenProject` an
optional display-name override — but the synthetic node needs no struct change.)

The `newProject` send is deferred to `onReady`, so the user sees `claude` boot
and then the prompt arrive and generation start — visible, honest progress. The
project immediately counts as a **running session** (its URL is in
`runningURLs`), so it's already pinned/green when the user goes back.

### How the dashboard reflects the new project

- The project appears as a real row **on the next scan**, once its `.project`
  marker exists on disk. To make this feel immediate rather than "on next app
  activation," **call `viewModel.rescan()` when returning to the dashboard from
  the just-created project** (extend the `onBack`/`openProject = nil` path for a
  new project to trigger a rescan), and rely on the existing
  `scenePhase == .active` rescan as the backstop. The durable answer is the
  FSEvents watcher (PROJECT.md §11) — when it lands, the marker's creation
  auto-refreshes the row and this manual rescan can be dropped. Note it as the
  follow-up; don't block MVP on it.
- Until the marker exists, the folder would scan as **untouched** — that's honest
  (it genuinely isn't set up yet) and self-heals to a project row the moment
  Claude writes `.project`. No fake "creating…" row is invented on the dashboard.

### Folder already exists / name clash

Prevented at the form (validation blocks a taken name, re-checking the real
directory at submit time, not just the cached scan). Defensive belt-and-braces:
if the `mkdir` still fails because the directory appeared in the race between
validation and submit, **do not proceed** — re-present the sheet with the name
field flagged **"A folder named "{name}" already exists here."** rather than
opening a session onto someone else's folder. The app must never send the
new-project prompt into a non-empty existing folder.

---

## 5. Edge cases

**No root folder connected.** The **New Project** toolbar button is **disabled**
(tooltip: *"Connect a root folder first."*), and the primary empty state remains
"Point AI Control at a folder → Choose Folder". Rationale: a target Location
(root or an organizer) is required (§9.2), so there's nothing valid to create
into yet. This is honest — the action isn't hidden, it's visibly not-yet-usable,
with the reason stated.

**No global config / no modules authored yet.** The AI needs modules to compile a
good `CLAUDE.md` (§6.2). Two honest sub-cases, both **allow-anyway with a quiet
inline warning** (auto mode, no approval ceremony — principle 4):

- **`~/.ai-control/` not set up** (`!globalConfig.isSetUp`): show a tertiary
  warning banner inside the sheet, above the buttons: **"Global config isn't set
  up. Projects normally inherit coding principles, workflow rules and secrets
  from `~/.ai-control/`."** with a **Set up…** button that opens the Global Config
  window (same action as the dashboard strip). The form stays fully usable.
- **Set up but `modules/` empty** (`isSetUp && !hasModules`): warning
  **"No global modules authored yet — the AI will create a minimal CLAUDE.md it
  can improve later."** Same **Set up…** affordance.

Do **not** block creation on either. The warning is guidance, in secondary/
tertiary text (no `attentionRed`, per the color rule); the user can proceed and
the AI degrades gracefully. This matches the honesty rule: state the real
situation, don't fake readiness and don't gate the flow.

**Organizer chosen but it later turns out to be an invalid nested organizer.**
Can't happen through the form — invalid nested organizers are never listed as
Location options (§2). No handling needed beyond not listing them.

**Description very long / multiline.** `sendLine` is paste-safe (types the text,
then Enter as a separate keystroke after the paste window — the Phase-5 lesson),
so a long INIT description submits correctly into Claude's TUI. No special
handling.

---

## MVP vs. deferred

**MVP (ships now):**
1. **New Project** toolbar button (gated on a connected root) + the empty-state
   action, both opening the sheet.
2. The sheet form: Name, Location (root + organizers), Visibility
   (Private default), required Description, with the live validation in §2.
3. On submit: app creates the **empty** target dir, opens a keyed session there,
   sends `newProject` base + appended params on `onReady`, and shows the project
   **full-window in `ProjectView`** so the build is watched live.
4. The AI does all authoring + GitHub + first commit (unchanged prompt).
5. Honest handling of the no-config / no-modules states (warn + allow) and the
   no-root state (disabled button).
6. Rescan-on-return so the new project row appears without an app relaunch.

**Deferred:**
- **FSEvents-driven auto-refresh** of the dashboard when `.project` appears
  (replaces the manual rescan-on-return). PROJECT.md §11.
- **Rich Location picker** (tree/breadcrumb) if organizer lists grow large — MVP
  flat menu is enough.
- **Post-create summary / template of what was created** — not needed; the live
  terminal already shows it, and files are the truth.
- **Editable "advanced" fields** (pre-selecting modules, pre-listing secrets) —
  the AI decides these from the description per §6.2; don't add form fields the
  AI is supposed to judge.
- **Duplicate-name suggestion** ("my-project-2") — MVP just blocks; auto-suggest
  is a nicety.

---

## Open calls for the engineer

1. **The `mkdir` is the app's only file write in this flow** — confirm this is
   the accepted reading of principle 2 (it matches the `createSkeleton()`
   precedent: empty structure yes, content no). If even that must move to the AI,
   the session-keying problem in §3 has to be solved another way first.
2. **Synthetic `AIControlNode` for `openProject`** vs. adding a display-name
   override to `OpenProject` — recommend the synthetic node (no struct change,
   `ProjectView` only reads name/url).
3. **`startNewProject` on `TerminalSessionStore`** mirrors `authorModules(at:)`
   (fresh-session `onReady` send). Confirm the store is the right home (it owns
   session lifecycle + prompt sending already).
4. **Rescan-on-return** is an interim seam for the FSEvents watcher; wire it so
   it's a one-line removal when the watcher lands.
5. **Visibility enum** — reuse the `.project` `visibility` vocabulary
   (private/public) so the appended block and the eventual `.project` agree.
