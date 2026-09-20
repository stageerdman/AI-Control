# UX notes — Global config: content & editing model

Design pass, content/authoring half of the global-config surface. No code.
Scope: **who authors each area, what ships, and how the user edits it.** The
window/menu structure is covered by a separate note — this one only defines the
content story. Builds on `ux-notes-global-config.md` (Phase 6) and must stay
consistent with its three global-config states and the drift/rebuild UX.

---

## 0. The principle-7 reconciliation (read this first)

The user set up global config, saw empty `modules/` and `wiki/`, and said they
"need pre-built files I guess." That pushes against principle 7 ("No templates")
and principle 2 ("the AI does the work, the app does not"). Here is the honest
resolution.

**Principle 7 is about the OUTPUT, not the INPUT.** Its exact words: "The AI
reads the global `.md` files and *builds each project* on its own judgement."
The thing forbidden from being templated is the **project** — the generated
`CLAUDE.md`, the folder scaffold, the setup. The global modules are the opposite
end of that sentence: they are *the source material the AI reads*. §6.2 states
plainly "On first launch **I create** the global modules." So global modules are
not a template of anything — they are the user's own standing instructions,
authored once and inherited everywhere. Giving them real content does not
violate principle 7. Principle 7 would only be violated if we shipped a
canned **project** or made the AI stamp projects from a fixed pattern.

**Principle 2 is the real constraint, and it is narrower than it looks.** Its
scope is explicit in §12 and §6: "The app does not run git and does not edit
**project** files itself." The app authoring *global module content* is a
different act from the app editing project files. But there is still a spirit
question: if the **app** ships hardcoded, opinionated module prose, that prose
is (a) generic (not the user's judgement, not the AI's judgement — the app's),
and (b) exactly the "template" smell the user's whole philosophy rejects, even
if it lives in `modules/` rather than a project. So: **the app should not author
module bodies.** That work belongs to the AI or the user.

**What the user actually wants** is not "let the app write my principles for
me." It is "after setup, don't leave me staring at empty folders — give me real
files I can read and edit." That desire is satisfiable **without** the app
templating anything, by having the AI produce the content. That is the whole
point of the app: the AI does the work.

### The recommendation: Option C (AI drafts modules from a short interview)

Ship the skeleton the app already ships (empty `modules/`, seeded `prompts/`,
`.env`, `wiki/`, `search.sh`) **plus** a one-time, opt-in flow where the AI
interviews the user briefly and writes real, personalized module files. The user
comes away with files to read and edit; the app never authored a word of
content; the modules are the user's judgement captured by the AI. This is the
only option that satisfies the user's ask **and** both principles at once.

| | (A) Ship empty, AI authors on first project use (today) | (B) App ships rich starter modules the user edits | (C) One-time AI interview drafts modules **(recommended)** |
|---|---|---|---|
| Principle 7 | Clean | Clean (modules ≠ project template) but *smells* like one | Clean |
| Principle 2 | Clean | **Violated in spirit** — app authors generic content | Clean — the AI does the authoring |
| User's "pre-built files" need | **Unmet** — empty folders, "needs global modules" wall until first project | Met — files exist immediately | Met — real files exist right after the interview |
| Personalization | Deferred, per-project | None — same prose for everyone | High — reflects this user's stack/taste |
| First-run friction | Low (nothing) but value is late | Lowest | One short interview |
| Risk | User feels the app is "empty / unfinished" (this is what happened) | Generic prose the user must gut; feels like boilerplate they didn't ask for | Interview must be genuinely short or it becomes a chore |

**Why not A:** it is what shipped, and it produced the exact complaint we are
resolving. The `modules/` folder sits empty until the *first project* forces the
AI to invent modules on the fly — the user has nothing to read, edit, or trust
in the meantime. Correct in principle, poor in felt experience.

**Why not B:** shipping fixed module prose makes the app an author of opinions.
It is the template pattern the user rejects, relocated to the global folder.
Even "good defaults" become boilerplate the user has to read and delete. It also
breaks the honesty model below (see §3): the app would be claiming modules are
"ready" when they are the app's guess, not the user's rules.

**Why C wins:** the AI — not the app — produces the files, so principle 2 holds.
The output is the user's own principles, captured in their words, so it is not a
template and principle 7 holds. And the user ends first-run with real,
readable, editable files, which is the thing they asked for.

**Bootstrap stays as-is.** Do **not** change `createSkeleton()` to write module
bodies. `modules/` stays empty at skeleton time. "Authored" = real content
written by the interview/AI, which is what flips the global state from "skeleton
created · no modules authored yet" to "ready · {n} modules." This keeps the
existing drift UX (§3 below) intact and honest.

### The interview flow (Option C), concretely

- **Trigger:** the Settings › GLOBAL CONFIG block. In the "skeleton created · no
  modules authored yet" state, offer a button **`Draft modules with AI`**
  alongside the existing honest sub-caption. It is pull, not push — no dashboard
  nag beyond the one-time setup strip already specced.
- **Mechanism (principle 2):** it is the same predefined-prompt → AI pattern as
  every other button. It opens/uses the **dashboard AI window** (root-scoped
  session, §8.4 — this is a global action, not a project one) and sends a new
  routine prompt, `author-modules` (see §5 for its text). The app writes nothing
  itself.
- **The interview:** the AI asks a *short* fixed set of questions (stack &
  language defaults, testing/commit discipline, UX taste + whether most projects
  even have UX, folder/structure conventions). The user answers in the CLI. The
  AI then writes `modules/UX.md`, `WORKFLOW.md`, `STRUCTURE.md`, `CODING.md`
  with real content, each led by the usage-description convention (§4), and
  commits. The `.project` file watcher / config reload picks up the new files
  and the global state self-heals to "ready · {n} modules."
- **Skippable:** a user who prefers to write modules by hand just opens the
  folder and does so (§2 editing model). Either path produces the same files.
- **Consistency with drift UX (§3):** until the interview produces real modules,
  every downstream surface honestly says "needs global modules." After, drift is
  computable. Nothing fakes readiness in between.

---

## 1. Authoring & editing matrix (who owns what)

| Area | Ships at bootstrap | Author | User edits how | App writes it? |
|---|---|---|---|---|
| `modules/*.md` | **Empty dir** (no files) | AI (interview, Opt. C) or user by hand | Reveal/Edit in Finder; later in-app editor | Never |
| `prompts/*.md` | **6 files, seeded defaults** | App seeds defaults; user overrides | In Settings (file-first, resettable) | Only the initial seed, never after |
| `wiki/*.md` | **Empty dir** + `search.sh` | User creates pages; AI appends lessons | Reveal/Edit in Finder | Never |
| `.env` | **Empty file** (header comment) | User (values); AI syncs into projects | Secrets window (masked) | Only the initial empty file |
| `README.md`, `.gitignore`, `search.sh` | Yes | App (infrastructure, not content) | Rarely; Reveal in Finder | Yes — these are plumbing |

The line is consistent: **the app writes structure and plumbing; the AI or the
user writes content.** `README`/`.gitignore`/`search.sh`/empty `.env` are
plumbing (app-owned, matches the existing skeleton). Module and wiki *content*
is never app-authored. `prompts/` is the one deliberate exception and it is a
safe one — see §5.

---

## 2. Editing experience (MVP) — in-app view + honest external edit

The user accepts "open the folder and edit files there." Make that honest and
frictionless without ever letting the app clobber a hand edit.

**MVP surface (per config area, inside the Settings window's global-config
region):**

- A **file list** for the area (modules, wiki pages, prompts). Each row: file
  name + its usage description / first line as a one-line preview.
- A **read-only preview pane** rendering the selected file's markdown. This is
  the "I can read my files" half the user wanted — satisfied even before an
  in-app editor exists.
- Per file, two actions: **`Edit in default editor`** (opens `$EDITOR` / the
  system default `.md` app) and **`Reveal in Finder`**. Standard macOS idioms;
  no bespoke editor to build for MVP.
- The preview is backed by the file watcher already in the app: edit the file
  externally, save, the preview refreshes. No "reload" button needed, no stale
  copy.

**Never silently overwrite (hard rule).** The app has exactly one path that
writes these files — the `prompts/` reset (§5) and the initial skeleton seed —
and both are `writeIfAbsent`-guarded or explicit user actions. The app must
**never** rewrite a file the user or AI has edited as a side effect of anything
else. In particular: re-running skeleton bootstrap is idempotent and must stay
so; a "reset prompt to default" is an explicit, per-file, confirmed action, not
a bulk operation.

**What a later in-app markdown editor would add (post-MVP, flagged not built):**
inline edit of the preview pane with save-on-blur, so the user never leaves the
app for a quick fix. When built it must (a) write only on explicit save, (b)
detect external modification since load (watcher mtime) and warn rather than
clobber, and (c) never touch a file the AI is mid-write on. Not needed for MVP —
"reveal + edit externally + live preview" is a complete, honest story.

---

## 3. The honesty problem — kept consistent with drift/rebuild

The Phase 6 note defined three global states and their downstream per-project
expression. Option C **preserves all of it unchanged** — that is a feature, not
a coincidence:

| Global state | Settings GLOBAL CONFIG line | Per-project CLAUDE.md row |
|---|---|---|
| `~/.ai-control/` absent | `— not set up` + `Create global config` | `— needs global config` |
| Skeleton exists, `modules/` empty | `Skeleton created · no modules authored yet` + `Draft modules with AI` | `— needs global modules` |
| Modules authored | `Ready · {n} modules` | drift computed (Problem 1) |

The only addition Option C makes to this table is the **`Draft modules with AI`**
button in the middle state, sitting right next to the existing honest
sub-caption. It converts the honest "not authored yet" state into an *actionable*
one without lying about readiness. Had we chosen Option B, the middle state
would vanish and the app would jump straight to "ready" while shipping content
the user never wrote — a faked readiness that contradicts the whole Phase 6
honesty stance. Option C is the only content choice that leaves the drift UX
truthful.

`hasModules` (in `GlobalConfigStore`) stays defined as **"module files with real
content exist"** — i.e. `config.modules` non-empty from actual authored files.
Do not create empty skeleton module files at bootstrap, or `hasModules` flips
true prematurely and "needs global modules" becomes a lie.

---

## 4. Per-area content specs

### 4.1 modules/ — what each file should contain (when authored, not shipped)

These outlines are the **shape the AI's interview fills and the user edits** —
NOT text the app ships. They double as the interview's question map. Every
module leads with the §6.4 usage-description convention so it is greppable and
so CLAUDE.md generation knows what each is for.

**`UX.md`** — usage line: "UX and interface rules; merged into CLAUDE.md only for
projects that have a UI."
- When this module applies (drop for non-UI projects — this is the §6.2 example).
- Design values (minimalism, reuse, standardized components — the repo already
  lives this).
- Component/isolation rules (UI highly isolated, built from reusable parts).
- Interaction/honesty conventions (e.g. never fake a status — mirrors this repo).

**`WORKFLOW.md`** — usage line: "How we work: git, updates, phases, commits.
Merged into every project."
- Back up in GitHub, commit after every change (the repo's own principles 1–2).
- Roadmap-with-phases, tests per phase, research phases as isolated experiments.
- Updates-folder convention (`updates/YYYY-MM-DD NAME - OPEN|CLOSED`, `update
  vX.md`, `wiki.md`).
- Wiki discipline: use `search.sh` before starting; write lessons back (§6.4).
- issues.txt discipline.

**`STRUCTURE.md`** — usage line: "The standard project folder layout the AI
creates and adopts against. Merged into every project."
- The §4 table (`.project`, `CLAUDE.md`, `.gitignore`, `.env`, `updates/`,
  `issues.txt`).
- `.project` frontmatter schema (§4 proposed block).
- Marker rules (`.project` / `.organize`, no nested organizers).

**`CODING.md`** — usage line: "Coding standards. Merged into every code project."
- Modular code, isolated contexts (principle 4 of CLAUDE.md).
- Stack-agnostic note (any stack per project; app itself is Swift).
- Language/testing/formatting defaults captured from the interview.

Recommend shipping **exactly these four** as the authored set — they are the
four named repeatedly across PROJECT.md (§6.1, §6.2, §9.1). More can be added by
the user/AI later ("whatever is needed"); do not pre-invent others.

### 4.2 prompts/ — confirm the file-first-with-default model

The current model is correct and needs no change; confirm it explicitly:

- `RoutinePromptKind` carries a built-in `defaultText`; `promptText(for:)`
  returns the stored file if present else the default. Behavior is identical
  whether or not the repo exists — this is the right design and is the one place
  app-shipped **content** is acceptable, because a routine prompt is app
  *behavior* (what a button does), not project or knowledge content. It is the
  app describing its own actions, which is squarely the app's job (principle 3:
  "Prompts are the app's main tool").
- **Editing:** Settings lists the 6 prompts by `title`; selecting one shows its
  effective text in the editable field. Save writes `prompts/<key>.md`.
- **Reset:** a per-prompt **`Reset to default`** action that deletes (or
  rewrites) `prompts/<key>.md` back to `defaultText`, confirmed, per file — never
  a bulk reset. After reset, `promptText` transparently falls back to the
  built-in default again.
- **Never overwrite on bootstrap:** `writeIfAbsent` already guarantees a
  re-scaffold won't stomp an edited prompt. Keep it.

**Critique of the 6 current defaults (read in full):** all six are accurate,
scoped, and match their §9 flows — no rewrites needed. Two small notes for the
user, not blockers:
- Neither `newProject` nor any prompt tells the AI to **use `search.sh` / write
  lessons to the wiki** (§6.4). That instruction belongs in the *modules*
  (WORKFLOW.md, per §4.1), which get merged into every CLAUDE.md — not in the
  routine prompts. So the defaults are correct to omit it; just confirm WORKFLOW
  carries it so it isn't lost.
- `newProject`, `adopt`, `newUpdate` reference "the description below" / "the
  name and definition below" — confirm the app appends the user's form input
  beneath the stored prompt when sending. This is the intended injection point;
  worth stating so no one treats the stored prompt as the complete message.

### 4.3 wiki/ — what ships, and the usage-description convention

- **Ships:** nothing but the empty `wiki/` dir and `search.sh` (already correct).
  No starter pages — a wiki page is user/AI knowledge, never app content. Do not
  seed example pages; an empty wiki with a working search is honest, a wiki
  pre-filled with fake "GoHighLevel" examples is not.
- **Author:** the user creates pages; the AI appends lessons without approval
  (§6.4). Both write real files; the app only reads and searches.
- **Usage-description convention (§6.4):** every page's **first non-heading line
  is a one-sentence usage description** — `search.sh` already extracts exactly
  this (`grep -m1 -vE '^\s*(#|$)'`) and prints it as the hit summary. Document
  this as the standing rule in WORKFLOW.md so every human- and AI-authored page
  follows it and stays findable. The in-app wiki file list (§2) shows this same
  first line as each page's preview — one convention, two consumers.

### 4.4 .env — names + values, masking, never committed

- **Ships:** the empty `.env` with its header comment (already correct) and
  `.gitignore` — but note: the skeleton `.gitignore` currently only lists
  `.DS_Store`. **`.env` is git-ignored in each *project* (§6.5) but the global
  `.env` lives in the private global repo and IS tracked there** (that is how
  values persist and sync). This is intentional per §6.5 ("keep this repo
  private") — flag it so no one "fixes" it by adding `.env` to the global
  `.gitignore`, which would lose the master secrets. Say it in the README.
- **Values:** real `KEY=value` pairs, edited in the **Secrets window** (§8.5),
  masked by default with reveal. The window shows which projects use each key.
- **Names vs values:** projects' `.project` lists secret **names only**;
  the app never surfaces a value into a project file — the AI syncs values via
  the `sync-secrets` prompt (§6.5). The app reads names from `.project`, values
  from the global `.env`, and never writes a value into any project.

---

## 5. New routine prompt to add: `author-modules`

Option C needs one new `RoutinePromptKind`. Proposed default text (edit to
taste in Settings like any other):

> Interview me briefly to author the global modules in `~/.ai-control/modules/`.
> Ask a short, focused set of questions — my default stack and languages, my
> git/commit/testing discipline, my folder-structure conventions, and my UX
> taste (and whether most of my projects even have a UI). Keep it to a handful
> of questions. Then write `UX.md`, `WORKFLOW.md`, `STRUCTURE.md` and
> `CODING.md`, each beginning with a one-sentence usage description on its first
> line so the wiki search and CLAUDE.md generation can tell what each is for.
> Base them on my answers and on PROJECT.md's conventions — these are my
> standing rules, not a template. When done, commit.

Add it to `RoutinePromptKind` (`case authorModules = "author-modules"`, title
"Author global modules"), so it seeds into `prompts/` and is user-editable like
the rest. It runs in the **dashboard AI window** (root session), since authoring
global modules is a global act, not a per-project one.

---

## 6. Open calls for the user / engineer

1. **Adopt Option C?** This is the product-defining call. Recommendation: yes —
   it is the only option honoring both principles and the user's "pre-built
   files" ask. (This project favors reacting to a live build; if C's interview
   feels heavy in practice, the fallback is A + hand-editing, still no
   templates.)
2. **`Draft modules with AI` placement:** confirm it belongs in Settings ›
   GLOBAL CONFIG (pull), not the dashboard (push). Recommend Settings only.
3. **Four modules as the authored set** (UX/WORKFLOW/STRUCTURE/CODING) — confirm,
   or name others up front. Recommend these four, extensible later.
4. **Global `.env` is tracked in the private global repo** (not git-ignored
   there) — confirm and document, so it isn't mistakenly ignored.
5. **MVP editing = view + reveal/edit externally, no in-app editor** — confirm
   deferral of the inline editor. Recommend deferring.
6. **Prompt injection point** (form input appended beneath stored prompt for
   newProject/adopt/newUpdate) — confirm the app does this on send.
