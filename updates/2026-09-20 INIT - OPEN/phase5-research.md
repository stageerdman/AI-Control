# Phase 5a research — awaiting-input detection via Claude Code hooks

Isolated experiment: `phase5-experiment/` (per CLAUDE.md principle 3). Goal:
decide how the app learns a session's state (working / awaiting-input / idle)
without parsing fragile terminal output. Decision: **Claude Code hooks writing
per-project status files the app watches** — validated end-to-end below.

## What was tested
Ran the real `claude` CLI (2.1.212) headlessly with an **app-owned settings
file** passed via `--settings`, registering command hooks that write a tiny
JSON status file per project folder:

```
claude -p "…" --settings phase5-experiment/hooks-settings.json
```

`hooks-settings.json` registers `SessionStart`, `UserPromptSubmit`, `Stop`,
`Notification`, `SessionEnd`; each runs `status-hook.sh`, which reads the hook's
stdin JSON and writes `<status-dir>/<sha1(cwd)>.json` (atomic write + rename)
plus an `events.log`.

## Results — it all works

**1. Hooks fire from a `--settings` file.** Full lifecycle observed in one
headless run (from `events.log`):

```
SessionStart     working        /private/tmp/exp-project-a
UserPromptSubmit working        /private/tmp/exp-project-a
Stop             awaitingInput  /private/tmp/exp-project-a
SessionEnd       stopped        /private/tmp/exp-project-a
```

So the state machine the app needs is directly available:
- **`Stop`** → Claude finished, **awaiting the user's next message** (the badge/
  notification trigger).
- **`UserPromptSubmit`** → user sent a message, back to **working** (clears it).
- **`SessionStart`** → **working**; **`SessionEnd`** → **stopped**.
- **`Notification`** (matcher `idle_prompt` / `permission_prompt`) → attention;
  less important under bypass mode but still wired.

**2. Hook stdin carries what we need to route it.** The status JSON written
from stdin:

```json
{ "cwd": "/private/tmp/exp-project-a",
  "event": "SessionEnd", "state": "stopped",
  "session": "df718808-ae10-4019-a674-03e44a9cbb7e" }
```

`cwd` + `session_id` are enough to map a hook back to its project folder.

**3. `bypassPermissions` works via `--settings`.** With
`"permissions": {"defaultMode": "bypassPermissions"}` in the settings file, a
tool-using prompt ("create proof.txt with your tools") ran with **no permission
prompt** and the file appeared. This matters: the docs say `bypassPermissions`
is refused from a project `.claude/settings.json`, but it **is** honored from a
file passed with `--settings` — which is exactly our delivery mechanism. So one
app-owned settings file gives us **both** hooks and auto-permission; we never
touch the user's `~/.claude/settings.json`.

## Two gotchas that shape the real implementation

**A. Quote the hook command — `/bin/sh` splits on spaces.** The first run set
`"command": "$AI_CONTROL_HOOK"`; because the script path contained a space
(`.../2026-09-20 INIT.../`), sh split it and the hook failed with
`No such file or directory`. Fix: quote inside the JSON —
`"command": "\"$AI_CONTROL_HOOK\""`. **The app ships its hook script under
`~/Library/Application Support/…` (a path with a space), so this quoting is
mandatory, not incidental.** Env-var expansion inside the command *does* work
(sh evaluates it), so referencing the script/status dir via env vars is fine —
they just must be quoted.

**B. `cwd` is symlink-resolved.** We launched in `/tmp/exp-project-a` but the
hook received `/private/tmp/exp-project-a` (`/tmp` → `/private/tmp`). So the app
**must canonicalize** (`URL.resolvingSymlinksInPath`) the project path before
comparing it to a status file's `cwd`, or it will never match. Plan: the pure
parser returns the raw `cwd` string; the store canonicalizes both sides when
matching status → project.

## Design the implementation locks in
- **Launch command:** `claude --settings <app-file> ` (bypass + hooks come from
  the file). The auto-launch stays a single string on `TerminalSession`.
- **Status transport:** hooks write `<app-status-dir>/<key>.json`; the app
  watches that directory (DispatchSource/FSEvents) and re-reads changed files.
- **Pure/tested seam (matches the Git parser lesson):** a `SessionStatusParser`
  turns one status-file's JSON into a typed `SessionActivity` + cwd; the store
  is the thin watcher that maps cwd → project URL and publishes
  `awaitingInputURLs`. Parser is exhaustively unit-testable; only the ~few lines
  of directory-watching are untested.
- **Stop routine reuses this:** after sending the stop-routine prompt, wait for
  the project's status to return to `awaitingInput`/`stopped` (Stop hook), then
  send `/exit` — no output scraping needed.

## Files
- `phase5-experiment/hooks-settings.json` — the app-owned settings shape.
- `phase5-experiment/status-hook.sh` — reference hook; the app ships a Swift-
  generated equivalent.
- `phase5-experiment/status/` — sample outputs (gitignored scratch).
