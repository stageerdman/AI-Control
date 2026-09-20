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

**In progress: Phase 0 and Phase 1.**

Done:
- Repo initialized, pushed to `https://github.com/stageerdman/AI-Control`
  (public).
- This project's own tracking files created: `.project`, `.gitignore`,
  `issues.txt`, this update.

Decisions made:
- Repo is public.
- Core domain logic (`AIControlCore`) is a separate Swift Package from the
  Xcode app shell, so it can be unit tested with `swift test` in isolation.
  See `wiki.md` for the full reasoning.

Next:
- Build `AIControlCore` (models + `FolderScanner` + `.project` parser) with
  unit tests.
- Scaffold the macOS app shell with `xcodegen`, wire it to the package,
  confirm it builds and launches a blank window.
