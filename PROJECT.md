# AI Control

A native macOS app (Swift) that organizes all of my projects around Claude Code, so I never repeat the setup work that comes with using AI: coding principles, `.md` files, folder structures, process structures, secrets, and lessons learned.

Claude Code lives in the CLI and runs on my subscription. AI Control does not replace it. It wraps it with an overview of every project, an embedded real terminal, and a shared global brain that every project inherits from.

---

## 1. Purpose

**Core purpose:** remove the repeating tasks connected to working with AI.

What gets automated:

- Setting up coding principles, workflow rules, UX rules and structure rules for every new project.
- Creating the same folder structure and tracking files in every project.
- Sharing knowledge between projects (for example, "how we control GoHighLevel") so it is figured out once.
- Sharing API keys and secrets between projects without copy-pasting.
- Keeping a clear history of what changed and why (updates), and what is still broken (issues).
- Giving me one dashboard over everything, ordered by what I worked on most recently.

**What the app is not:** it is not a chat product and not an AI itself. All intelligence comes from Claude Code in the CLI. The app is the organizer, launcher and viewer.

---

## 2. Core principles

1. **Files are the only truth.** All state lives in files (`.project`, `updates/`, `issues.txt`, `CLAUDE.md`, global config). The app watches and renders them. Everything must still work if the app is closed.
2. **The AI does the work, the app does not.** Git, updates, CLAUDE.md generation, project setup, adoption, secret syncing and lesson-saving are all done by Claude Code, triggered by prompts the app sends. The app never edits project files itself.
3. **Prompts are the app's main tool.** Most buttons simply send a stored prompt to a Claude Code session. Those prompts are editable in a Settings window.
4. **Auto mode, no approval ceremony.** Claude runs in auto mode. I do not approve generated CLAUDE.md files or wiki writes. When Claude does need me, the app must make that obvious.
5. **Use the real CLI.** A real terminal is embedded and the app can read from it and write to it.
6. **No chat storage by the app.** The app does not store conversations.
7. **No templates.** The AI reads the global `.md` files and its own setup instructions and builds each project on its own judgement.
8. **Any stack for projects.** The app itself is Swift. Projects inside it can use any stack.

---

## 3. Concepts and folder conventions

### 3.1 Root folder

The app connects to **one root folder** (for example `/dev`). It shows every project and organizer found inside it. The root itself needs no marker.

### 3.2 Organizer

- A single real folder that contains project folders (for example `/dev/organizer`).
- Marked by a **`.organize`** file inside it.
- **Nested organizers are not allowed.** If found, I talk with the AI about fixing it.

### 3.3 Project

- A folder holding one piece of work, usually code (for example `/dev/code/my-app`), but it can be any kind of project.
- Marked by a **`.project`** file inside it.
- A project can sit directly in the root or inside an organizer.

### 3.4 Under AI Control vs untouched

- **Under AI Control:** the folder contains `.organize` (organizer) or `.project` (project).
- **Untouched:** the folder has neither marker. The app shows it as not under AI Control. The app does not try to classify it. The AI checks it and decides what it is and what to do with it (see 8.4 and 9.3).

---

## 4. Project structure (defined by `STRUCTURE.md`)

Every project under AI Control contains:

| Item | Purpose |
|---|---|
| `.project` | Marker plus metadata: description, how-to-use, status text, GitHub connection, CLAUDE.md generation info, secrets used. Machine-readable frontmatter plus human-readable body. Read by the app for the sidebar. |
| `CLAUDE.md` | Compiled instructions for Claude Code, generated from the global modules and adjusted to this project. |
| `.gitignore` | Present by default, always covering `.env`. |
| `.env` | Secrets this project needs, sourced from the global `.env`. |
| `updates/` | One folder per update (see section 5). |
| `issues.txt` | Timestamped list of recently discovered, unresolved issues. Updated after every update. |

Every organizer contains `.organize` and its project folders.

### `.project` format (proposed)

```yaml
---
name: my-project
github: https://github.com/<user>/my-project
visibility: private
adopted: 2026-09-20
claude_md_generated: 2026-09-20
modules: [WORKFLOW, STRUCTURE, CODING]
secrets: [GHL_API_KEY, OPENAI_API_KEY]   # names only, never values
---
```

The body holds: project description, a short how-to-use, and a status text. The AI keeps these current.

---

## 5. Updates system

Every project has an `updates/` folder. **Only the AI creates and controls updates.**

### 5.1 Folder naming

```
updates/YYYY-MM-DD UPDATE_NAME - OPEN
updates/YYYY-MM-DD UPDATE_NAME - CLOSED
```

The AI renames the folder between OPEN and CLOSED.

### 5.2 Contents of an update folder

- **`update vX.md`** (X starts at 1). Holds the goal, the roadmap to achieve it, and status tracking: what was done, what decisions were made, what is next.
- **`wiki.md`**. Decisions and lessons about what works and what does not for this update: principles and lessons learned.
- **Optional extra files** for logging anything else related to the update.

### 5.3 Reopening

If something needs fixing or finishing later, the AI reopens the same update: it creates `update v2.md` (then v3, and so on), the folder becomes OPEN again, and we always work with the latest version file.

### 5.4 Issues

`issues.txt` at the project root lists recently discovered, unresolved issues with timestamps. The AI updates it after each update. The app shows it in the sidebar.

### 5.5 First update

Every new project starts with an **INIT update**, whose description is the INIT text I provided at creation.

---

## 6. Global configuration

Lives in its own git repo, proposed at `~/.ai-control/`. It is shared by all projects.

### 6.1 Proposed layout

```
~/.ai-control/
  modules/        UX.md, WORKFLOW.md, STRUCTURE.md, CODING.md, ... (whatever is needed)
  wiki/           knowledge pages (GoHighLevel, Stripe, ...)
  prompts/        editable routine prompts (see 8.6)
  .env            global secrets and variables
  search script   searches the wiki
```

### 6.2 Modules and CLAUDE.md generation

- On first launch I create the global modules (UX.md, WORKFLOW.md, STRUCTURE.md, CODING.md, or whatever we decide is necessary).
- For each project, the AI **merges the relevant modules into one `CLAUDE.md`**, using its own judgement based on the project description. For example it drops `UX.md` when the project has no UX.
- It may adjust wording slightly for the project. There is **no approval step**.
- The project can override or add local rules freely.
- Which modules were used and when the file was generated are recorded in `.project`.

### 6.3 Drift and rebuild

- The app compares the generation date in `.project` with the modification dates of the global modules.
- If any module changed after that date, the project sidebar shows **"CLAUDE.md out of date"** with a **Rebuild** action.
- Rebuild sends a prompt to Claude Code in the project's CLI. The AI regenerates `CLAUDE.md` and checks whether important rules were adjusted locally, so they are kept.

### 6.4 Knowledge wiki

- One folder of pages, inspired by the LLM-wiki approach: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
- Each page stores how we work with a certain thing (for example GoHighLevel): API notes, gotchas, principles, working snippets.
- Each page has a **usage description** at the top so it can be found by search.
- A **small search script** on top of the wiki lets any AI find relevant pages. `CLAUDE.md` tells the AI to use it.
- **The AI can write lessons back to the wiki without approval.**

### 6.5 Secrets

- Master secrets and global variables live in the **global `.env`** in the AI Control repo. This repo must therefore stay private.
- Each project's `.env` is generated by the AI with only the keys that project needs. Keys can be added, removed or updated at any time.
- Every project has `.gitignore` covering `.env`.
- Project `.project` lists secret **names** used, never values, so the sidebar can show them.
- **When a global secret changes**, projects using that key are flagged as out of date. Syncing happens through a prompt sent to the project's CLI, the same way as a CLAUDE.md rebuild. The app never edits project `.env` files itself.

---

## 7. Sessions (Claude Code in the CLI)

- Each project gets its own Claude Code session in an embedded real terminal, started in the project folder, in auto mode.
- Sessions keep running when I go back to the dashboard.
- **Running sessions are pinned on top of the dashboard with a green indicator.**
- **Awaiting input:** if a session asks for approval or a question, the project gets a notification, a badge and a highlight on the dashboard.
- **Stop routine** (right-click a project, then Stop): the app interrupts the task in progress, sends the stop routine prompt (saves state so we can continue later, commits and pushes), waits until Claude is done, then exits the CLI. Mid-task crashes are ignored. The interrupted task is simply not resumed.
- Chat history is **not stored by the app**.

---

## 8. UI and features

### 8.1 Dashboard

- Opening the app shows a **single list of all projects and organizers**, mixed together, **ordered by recency of last chat**.
- **Search** across the whole list.
- **Organizers** can be clicked to show the projects inside them. Organizer recency equals the most recent chat among its projects.
- **Projects** can be clicked to select them and show the sidebar. **Double-clicking** a project opens its CLI chat.
- **Running sessions are pinned on top** with a green indicator, and awaiting-input sessions are highlighted with a badge and notification.
- Untouched folders are visibly marked as not under AI Control.
- Right-click menu (see 8.4): **AI**, **Stop** (for running sessions).
- A **New Project** button.
- A **dashboard AI window** (see 8.4).
- Entry points to the **Secrets window** and **Settings window**.

### 8.2 Project sidebar (single click on the dashboard)

- Project description.
- Whether it is under AI Control.
- Out-of-date indicators: CLAUDE.md older than global modules, secrets out of sync.
- Secrets it uses (names only).
- GitHub connection and status.
- Last chat time and token usage (see section 10).
- Other important details from `.project`.
- For untouched folders: an action to bring it under AI Control (see 9.3).

### 8.3 Project view (double-click)

A CLI-like chat with Claude Code fills the main area, where I describe anything. The side panel now shows:

- **Recent updates** (from `updates/`, with OPEN and CLOSED state).
- **How-to-use** and **status text** of the project (from `.project`).
- **Issues**: a scrollable list of unresolved discovered issues (from `issues.txt`).
- **GitHub:** connected or not, and whether the latest work is successfully committed (clean tree, unpushed commits, last commit). The app only reads git state here.
- **New Update** button: opens a small form for update name and definition text. The app sends this to Claude in the CLI, and the AI creates the folder and `update v1.md` (see 9.4).
- **Back to dashboard** button. The session keeps running.

### 8.4 AI window and the right-click "AI" action

- The dashboard contains a small **AI window**: a Claude Code session started at the root folder, for general questions and for handling untouched folders.
- Right-clicking any project or folder shows an **AI** option. It passes that folder's path to the dashboard AI window as a reference, and I can ask about it there. This is the way to get an AI verdict on an untouched folder.

### 8.5 Secrets window

- One window showing **all secrets** from the global `.env`.
- Add, edit, remove secrets easily. Values masked by default with an option to reveal.
- Shows which projects use each secret.
- Changing a secret flags affected projects as out of date (see 6.5).

### 8.6 Settings window

- Manage the **routine prompts** stored in `~/.ai-control/prompts/`, so the AI knows exactly what to do. The list:
  - Stop and save routine (default idea: "finish everything up, we'll get back to this later")
  - New project setup
  - Bring existing project under AI Control
  - Rebuild CLAUDE.md
  - Sync secrets
  - New update
- Connect or change the root folder.

---

## 9. Key flows

### 9.1 First launch

1. Connect the root folder.
2. Set up global instructions: create the modules (UX.md, WORKFLOW.md, STRUCTURE.md, CODING.md, ...).
3. Add global secrets and variables to the global `.env`.
4. Dashboard shows everything found in the root folder.

### 9.2 New project

1. Click **New Project**.
2. Enter the project name, the target location (root or an organizer), **private or public**, and a **detailed INIT description** of what I want (required).
3. The app opens a session and sends the new-project prompt. The AI then:
   - selects the relevant modules and compiles `CLAUDE.md`,
   - creates the default structure from `STRUCTURE.md` (`.project`, `.gitignore`, `.env`, `updates/`, `issues.txt`),
   - creates the first **INIT update** with my description,
   - creates the GitHub repo with the chosen visibility, connects it, and makes the first commit.

### 9.3 Bring an existing project or folder under AI Control

1. Select an untouched folder. The sidebar offers to bring it under AI Control, or I use the right-click **AI** option.
2. The AI analyzes the folder against `STRUCTURE.md`, decides whether it is a project or an organizer, and **reports the result in the CLI**.
3. If I say go for it, the AI makes the changes.

### 9.4 New update

1. Click **New Update** in the project view.
2. Enter the update name and definition.
3. The app sends them to Claude. The AI creates `updates/YYYY-MM-DD NAME - OPEN/` with `update v1.md` and `wiki.md`.

### 9.5 Working on a project

1. Double-click the project, tell Claude the next steps, and it implements them.
2. The AI tracks progress in the update files, records lessons in the update wiki and global wiki, updates `issues.txt`, and handles git.
3. Press **Back to dashboard** to work elsewhere while the AI keeps running.

### 9.6 Rebuild or sync

1. Sidebar shows an out-of-date indicator (CLAUDE.md or secrets).
2. Click Rebuild or Sync. The matching prompt is sent to the project's CLI and the AI handles it.

### 9.7 Stop a project

1. Right-click the project, then Stop.
2. The app interrupts, runs the stop routine, waits for completion, and exits the CLI.

---

## 10. Data the app reads

- **Last chat time:** taken from Claude Code's own local session logs (read-only), not stored by the app.
- **Token usage:** the same logs contain token counts, so the app can show per-project totals. Subscription usage has no dollar cost, so it shows tokens only. The exact log format and location must be verified at implementation.
- **Git state:** read-only queries for the GitHub status.
- **Projects, updates, issues, secrets names:** read directly from files, with a file watcher for live updates.

---

## 11. Technical requirements

- Native macOS app in **Swift** (SwiftUI). Runs as a normal `.app`.
- **Embedded real terminal** (PTY-based terminal emulator, for example SwiftTerm), one per session.
- The app needs programmatic access to each terminal: **send input** (prompts, interrupt, exit) and **read output** (detect idle, detect awaiting input).
- Multiple sessions alive at once, surviving navigation between dashboard and project view.
- Detecting "awaiting input" can use terminal output or Claude Code hooks. Decide at architecture stage.
- File watching (FSEvents) so the dashboard reacts to changes on disk.
- No database. Files are the only source of truth.
- macOS notifications and a Dock badge for awaiting-input sessions.
- Claude Code launched in auto permission mode. The exact flag is to be confirmed at implementation.
- GitHub operations done by the AI, using the `gh` CLI, which must be installed and authenticated.

---

## 12. Non-goals

- The app does not create templates, and does not manage MCP servers.
- No separate verification rules system. Verification rules are written in `CLAUDE.md`.
- No approval flow for generated `CLAUDE.md` or wiki writes.
- The app does not run git and does not edit project files itself.
- No chat history storage or search.
- No nested organizers.
- Not multi-user: built for a single user.

---

## 13. Assumptions and open items

Assumptions made in this document, to confirm during architecture:

- Marker names are `.organize` and `.project`.
- `.project` is Markdown with a frontmatter block.
- Global config lives at `~/.ai-control/` as its own private git repo.
- Projects and organizers with no chat yet sort below those with chats, alphabetically.
- Organizer recency equals the most recent chat among its projects.
- New Update button sends a prompt to the AI rather than creating files itself.
- Closing the app with running sessions should offer to run the stop routine on each of them.
- Secret out-of-date detection compares the project's `.env` values against the global `.env` per key, and needs a way to handle intentional local overrides.
- Token usage and last chat time can be read from Claude Code's local logs.
