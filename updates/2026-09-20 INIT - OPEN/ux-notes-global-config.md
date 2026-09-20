# UX notes — Global config: CLAUDE.md drift/rebuild + first-launch bootstrap

Design pass for Phase 6. No code. Hand to engineer. Reuses the existing
minimalist sidebar system (`SidebarSection`, `SidebarKeyValue`,
`SidebarHeader`, `FlowLayout`, `BannerActionButtonStyle`). Respects the two
standing constraints:

- **Honesty:** never fake a status. Deferred/uncomputable data is a neutral,
  uncolored `— …` note (the `placeholder` flag on `SidebarKeyValue`), never an
  invented green/red and never a dead button. An action appears **only** when a
  real out-of-date state exists.
- **`attentionRed` is reserved for awaiting-input only.** Drift is
  informational, not an alarm — it gets **no** alarm color. Meaning is carried
  by wording + the presence of the changed-module list and Rebuild button, the
  same "shape/text over color" line as the Phase 5 awaiting-input work.

---

## Problem 1 — CLAUDE.md drift indicator + Rebuild

### Where it lives

Replaces the current placeholder row in `maintenanceSection` of
`ProjectDetail` (ProjectSidebarView.swift):

```
SidebarKeyValue(key: "CLAUDE.md drift", value: "not available yet", placeholder: true)
```

Keep it as the first row of the existing **MAINTENANCE** `SidebarSection`.
Do not reshuffle section order (Activity/Details stay put). The "Secret sync"
row directly below is the exact same pattern (§6.5) and should track these same
states — keep the two visually parallel.

### State model

The row's state is a function of **two** inputs: whether global modules exist at
all, and — if they do — the project's `claude_md_generated` date vs. the mtimes
of the modules listed in `.project`'s `modules:`. Gate on module existence
first; drift is uncomputable without modules.

| Condition | Key | Value (SidebarKeyValue) | Changed list | Button |
|---|---|---|---|---|
| No `~/.ai-control/` at all | `CLAUDE.md` | `— needs global config` (placeholder) | — | none |
| Config exists, `modules/` empty | `CLAUDE.md` | `— needs global modules` (placeholder) | — | none |
| Modules exist, `claude_md_generated` absent | `CLAUDE.md` | `Not generated yet` (real, secondary — **not** dimmed) | — | `Generate` (optional, see below) |
| Modules exist, generated ≥ all module mtimes | `CLAUDE.md` | `Up to date` (real, secondary) | — | none |
| Modules exist, ≥1 module mtime > generated | `CLAUDE.md` | `Out of date` (real, secondary) | chips of changed modules | `Rebuild` |

Notes:
- The first two rows are genuinely uncomputable → `placeholder: true` (dim,
  em-dash prefix), matching today's honesty rule. The degraded copy differs from
  today's blanket "not available yet" because we now know *why* (no config vs.
  no modules) — say the specific thing.
- `Not generated yet` / `Up to date` / `Out of date` are **real** computed
  states → full `SidebarKeyValue` (no `placeholder`, secondary value color). No
  green tick, no red. This is deliberate: "Up to date" vs "Out of date" is
  distinguished by the changed-module list + button appearing beneath, not by
  color. Reserve color for awaiting-input.

### Layout & component reuse

Out-of-date state, top to bottom inside the MAINTENANCE section:

1. `SidebarKeyValue(key: "CLAUDE.md", value: "Out of date")` — the status line.
2. A **"Changed" sub-line**: reuse the wrapping chip pattern. The chips are
   monospaced module names, same visual language as `SecretChips` /
   `FlowLayout` (already in SidebarComponents.swift) — do not invent a new
   list style. Prefix with a tertiary caption `Changed since generated`.
   - Chip = bare module name (`WORKFLOW.md`, `CODING.md`). Names only, calm gray
     chip (`Color.gray.opacity(0.12)`), exactly like secret chips. No red.
   - If you want per-module recency, put it in a chip tooltip (`.help(...)`),
     e.g. `Changed 2d ago` — keep the chip itself just the name so the row stays
     quiet.
3. The **Rebuild button** (see below).

Up-to-date and the two degraded states are a single `SidebarKeyValue` line with
no follow-on content — the section stays one tight list.

Optional affirmative detail for "Up to date": a tertiary trailing note
`· generated {relative}` reusing `SidebarFormat.relativeString`. Keep it on the
same visual weight as other captions; it is not a status badge.

### Rebuild button — placement, interaction, feedback

**Placement:** a `.bordered` button beneath the changed-module chips, left
aligned, inside the same `VStack(alignment: .leading, spacing: 4)` idiom used by
the untouched-folder "Bring under AI Control" block. Label `Rebuild`, SF Symbol
`arrow.triangle.2.circlepath` (a calm "regenerate" glyph, not an alarm).

**Mechanism (do not deviate from principle 2):** Rebuild is the same
predefined-prompt → AI pattern as "Bring under AI Control" / "Let AI fix it"
(see wiki: *"The two AI-action buttons are one pattern"*). It sends the stored
`Rebuild CLAUDE.md` routine prompt (§8.6, `~/.ai-control/prompts/`) into **this
project's own Claude Code CLI session** — not the dashboard AI window (that's
for untouched folders / general questions; a project has its own session). The
app never touches `CLAUDE.md` itself. Model it as
`(projectURL, promptKind: .rebuildClaudeMd)` routed through the same plumbing
the other routine prompts will use.

**Programmatic-input reminder (wiki, Stop-routine lesson):** send the prompt via
`sendLine` — type the text, then send `\r` **alone ~0.25s later** (Claude's TUI
paste detection eats an appended CR). Any routine prompt sent to a session must
do this.

**Confirmation:** no modal in the normal case — auto mode means no approval
ceremony (principle 4). Single click sends. The **one** guard: if the project's
session is currently `working` or `awaitingInput` (we already track this via the
status hooks / `SessionActivity`), a rebuild would interleave with in-flight
work — show a lightweight confirm first:

> **Claude is busy in this project.** Sending Rebuild now will queue it after
> the current message. Send anyway?  — [Send] [Cancel]

If no session is running yet, sending Rebuild starts one in the project folder
(same launch path as double-click) and then sends — no dialog.

**Feedback (async, happens in the terminal):** the app must not optimistically
flip the row to "Up to date" — that would be a faked status. Instead:

1. On send, replace the Rebuild button with a dim, non-interactive line:
   `Rebuilding… — Claude is regenerating CLAUDE.md in the terminal` plus a
   small `Open session` text button (opens the project view so the user can
   watch — reuses the existing double-click-to-open path).
2. Leave the status value as `Out of date` while rebuilding — it is still out of
   date until proven otherwise.
3. When Claude finishes, it rewrites `.project`'s `claude_md_generated`. The
   existing `.project` file watcher recomputes drift and the row **self-heals**
   to `Up to date`, the changed chips disappear, the "Rebuilding…" line is
   gone. No polling of the button state needed — disk is the truth.
4. If nothing changes on disk within the session's lifetime, the row simply
   stays `Out of date` with the Rebuild button restored — honest, no error
   invented by the app.

### Exact microcopy (Problem 1)

- Key label: `CLAUDE.md`
- Values: `Up to date` · `Out of date` · `Not generated yet` ·
  `— needs global modules` · `— needs global config`
- Changed sub-line caption: `Changed since generated`
- Up-to-date trailing note: `· generated {relative}` (e.g. `· generated 3d ago`)
- Button: `Rebuild` (symbol `arrow.triangle.2.circlepath`);
  first-generation variant `Generate`
- Busy confirm: `Claude is busy in this project. Sending Rebuild now will queue
  it after the current message. Send anyway?` — buttons `Send` / `Cancel`
- In-flight line: `Rebuilding… — Claude is regenerating CLAUDE.md in the
  terminal`, trailing text button `Open session`

Optional `Generate` (first-generation, state "Not generated yet"): same
mechanism and prompt as Rebuild. Reasonable to ship, since an adopted project
with modules but no generated file wants exactly this. If it feels like scope
creep, leave state "Not generated yet" button-less for now — it is an honest
non-action, not a dead button.

---

## Problem 2 — first-launch global-config bootstrap

The problem is **global**, not per-project, so it must not be per-project sidebar
chrome, and it must not nag. There are two honest facts to communicate: (a) the
config repo may not exist, and (b) even after the app scaffolds it, the *module
content is not authored yet* (authoring needs the AI window, a later phase).

### Surface & placement

Two surfaces, both quiet:

1. **One-time dashboard strip — only while `~/.ai-control/` is entirely
   absent.** A slim, neutral informational strip at the top of the dashboard
   (NOT the `attentionRed` banner — that is reserved; this is not "your turn",
   it's setup). Neutral surface (`.background` / subtle material), one line of
   text + one button. It disappears permanently the moment the skeleton exists
   and never returns. This is the only proactive prompt; everything else is
   pull, not push.

2. **Persistent, quiet status in the Settings window (§8.6).** Settings already
   owns `~/.ai-control/` (it manages the routine prompts there), so it is the
   natural permanent home for global-config state. A single `SidebarSection`-
   style block: `GLOBAL CONFIG` with a `SidebarKeyValue` line and, when
   relevant, a `Create global config` / (later) authoring affordance. This is
   where the user goes deliberately — no nagging.

Do **not** put a global-config banner inside the project view or repeat it per
project.

### What the "Create global config" action does

App-side scaffolding only (this is sanctioned — it's empty structure, not
authored content, and not a *project* file, so principle 2 is intact):

- create `~/.ai-control/` with empty `modules/` and `wiki/` dirs
- seed the default routine prompts into `prompts/` (Stop, New project, Adopt,
  Rebuild CLAUDE.md, Sync secrets, New update — §8.6)
- create an empty `.env`
- drop in the wiki search script
- `git init`

It explicitly does **not** author any module — that is the AI's job in the
future AI-window phase. Say so plainly (see copy).

### Honest global-config states

| Global state | Dashboard strip | Settings GLOBAL CONFIG line | Per-project CLAUDE.md row |
|---|---|---|---|
| `~/.ai-control/` absent | shown | `— not set up` (placeholder) + `Create global config` button | `— needs global config` |
| Skeleton exists, `modules/` empty | hidden | `Skeleton created · no modules authored yet` (real) | `— needs global modules` |
| Modules authored | hidden | `Ready · {n} modules` (real) | drift computed (Problem 1) |

The middle state is the crux of the honesty constraint: after scaffolding, the
config **exists** but is not usable for CLAUDE.md generation. We say exactly
that — "no modules authored yet" — rather than implying readiness. The
per-project drift row's degraded value (`— needs global modules`) is the
downstream expression of the same truth, and it is a dim placeholder (not a
computed status) precisely because drift can't be computed with zero modules.

### Exact microcopy (Problem 2)

Dashboard strip (config absent):
- Text: `Global config isn't set up. Projects share coding principles,
  workflow rules and secrets from ~/.ai-control/.`
- Button: `Create global config`

After creation (transient confirmation — inline caption or brief toast, not a
modal):
- `Created ~/.ai-control/ (skeleton). Modules aren't authored yet — that happens
  with the AI in a later phase.`

Settings GLOBAL CONFIG section:
- Key: `Global config`
- Values: `— not set up` · `Skeleton created · no modules authored yet` ·
  `Ready · {n} modules`
- Button (absent state): `Create global config`
- Sub-caption under skeleton state: `Modules are authored by the AI (coming in
  a later phase). Routine prompts, .env and the wiki search script are ready.`

Per-project degraded values (already in the Problem 1 table):
- `— needs global config` (nothing exists)
- `— needs global modules` (skeleton but empty)

---

## Open calls for the engineer

1. **Drift computation lives in `AIControlCore`, tested** (per the repo's
   modular line): a pure function `(claudeMdGenerated: Date?, moduleMtimes:
   [String: Date]) -> DriftState` with the enum `.noConfig / .noModules /
   .notGenerated / .upToDate / .outOfDate(changed: [String])`. The App target
   just renders it. Feed it the module list from `.project`'s `modules:`.
2. **Module mtime source:** confirm we compare against `modules/*.md` file mtimes
   in the git working tree (simple, matches §6.3) rather than git commit dates.
   Working-tree mtime is fine and simpler; note it so it isn't second-guessed.
3. **Which modules to compare:** only the modules named in `.project`'s
   `modules:` array (a project that dropped `UX.md` shouldn't drift on UX
   changes). Confirm `.project` reliably carries that list post-generation.
4. **First-generation `Generate` button:** ship it or leave state
   "Not generated yet" button-less? Recommend shipping (same prompt/mechanism as
   Rebuild) but flag for the user's live-test call — this project favors
   reacting to a real build over spec.
5. **Busy-session guard:** confirm the confirm-dialog trigger reads
   `SessionActivity` state; decide whether "no session running" should
   auto-start one on Rebuild (recommended) or ask first.
6. **Skeleton creation ownership:** confirm the app doing the `git init` +
   scaffold is acceptable (it's structure, not authored/project content). If the
   user would rather even the skeleton be AI-driven, this collapses to a
   predefined-prompt action instead — but then first launch has no config at all
   until a session runs, which is worse UX.
7. **Secret-sync row parity:** it shares this exact state machine (§6.5,
   global-`.env`-key-change → project out of date → Sync prompt). Build both off
   the same pattern so they stay visually and behaviorally parallel in the
   MAINTENANCE section; don't design Sync separately later.
