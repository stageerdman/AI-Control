# Phase 4 research — SwiftTerm PTY embedding

Isolated experiment: `phase4-experiment/` (a throwaway SPM package that pulls
SwiftTerm so its real API could be read from source, per CLAUDE.md principle 3).

## Dependency
- **SwiftTerm**, `https://github.com/migueldeicaza/SwiftTerm.git`, `from: "1.2.0"`
  resolves to **1.20.0**. Transitively pulls `swift-argument-parser` (used by
  SwiftTerm's own demo targets; harmless for us).
- Pure Swift, AppKit-based on macOS. So the terminal code lives in the **App
  target**, not `AIControlCore` (which stays UI-free). This is the right
  modular line: `AIControlCore` = logic + tests; App = SwiftUI/AppKit glue.

## The class we use: `LocalProcessTerminalView`
An `open` AppKit `NSView` subclass that runs a child process inside a real
pseudo-terminal. Everything Phase 4 needs is on it:

- **Launch (with working directory):**
  `startProcess(executable: String = "/bin/bash", args: [String] = [], environment: [String]? = nil, execName: String? = nil, currentDirectory: String? = nil)`
  → pass the **project folder** as `currentDirectory`.
- **Send input programmatically:** `send(txt: String)` (also `send(data:)` /
  `send(_ bytes:)`), inherited from `TerminalView`. This is exactly the app's
  "send input (prompts, interrupt, exit)" requirement (PROJECT.md §11).
- **Read output:** `dataReceived(slice: ArraySlice<UInt8>)` is `open`. Subclass
  and override it to **tee** the raw process→terminal bytes to a callback, then
  call `super` so the terminal still renders. This is the "read output (detect
  idle, detect awaiting input)" hook Phase 5 will build on.
- **Lifecycle/metadata:** set `processDelegate` (a
  `LocalProcessTerminalViewDelegate`) for `processTerminated(exitCode:)`,
  `setTerminalTitle`, `hostCurrentDirectoryUpdate`, `sizeChanged`.
- **Do not** reassign `terminalDelegate` — `LocalProcessTerminalView` sets and
  consumes it internally; overriding it breaks the PTY wiring. Use
  `processDelegate` and the `dataReceived` override instead.

## Environment gotcha → launch a login shell
`Terminal.getEnvironmentVariables()` (the default when `environment: nil`) sets
`TERM=xterm-256color`, `COLORTERM`, `LANG`, and copies `HOME`/`USER` — but
**deliberately omits `PATH`**. So a bare `/bin/bash` wouldn't find `git`,
`gh`, or `claude`. Fix: launch the user's **login shell** so it sources the
profile and sets `PATH` itself — `executable = $SHELL` (fallback `/bin/zsh`),
`args = ["-l"]`, `environment = nil`. Interactive-login gives a real usable
shell in the project directory.

## Sandbox
`LocalProcessTerminalView` needs the app **unsandboxed** (its own docs say so),
or the shell can't reach the filesystem/commands. AI Control already ships
unsandboxed (`ENABLE_HARDENED_RUNTIME: NO`, no sandbox entitlement, see
`App/project.yml` and the RootFolderStore note) — nothing to change.

## Integration plan (implemented in the App target)
- `TerminalSession` (ObservableObject): owns one subclassed
  `LocalProcessTerminalView`, starts it at a project's folder, exposes
  `send(_:)`, a running/terminated flag, and an output tee. One per project.
- `TerminalSessionStore`: `[URL: TerminalSession]`, so a project's session is
  created once and **survives navigation** between dashboard and project view
  (PROJECT.md §11) — held as a `@StateObject` on the root view.
- `TerminalContainerView` (`NSViewRepresentable`): hosts the session's view.
- `ProjectView`: shown on **double-click** of a project — terminal fills the
  main area, with a "Back to dashboard" control; the session keeps running when
  you go back (§8.3).

## Build-integration gotchas (SwiftTerm via xcodebuild)
Two things break a clean command-line build the first time SwiftTerm is added:
1. **Package build-tool plugin validation.** SwiftTerm ships a
   `SwiftTermBuildInfoPlugin`; `xcodebuild` refuses to run it unattended and
   fails with *"Validate plug-in SwiftTermBuildInfoPlugin"*. Fix: pass
   **`-skipPackagePluginValidation`** to `xcodebuild`.
2. **Metal toolchain.** SwiftTerm includes `Shaders.metal`; recent Xcode makes
   the Metal compiler a separate downloadable component, so the build fails
   with *"cannot execute tool 'metal' due to missing Metal Toolchain"*. Fix
   (one-time, per machine): **`xcodebuild -downloadComponent MetalToolchain`**.
   **Gotcha (2026-09-20):** this command **stalls at 0 bytes when run from the
   agent's non-interactive shell** — the asset only downloads from a real
   user terminal (or Xcode → Settings → Components), where it can
   authenticate. Once run there it installed fine (`Status: installed`,
   `xcrun metal --version` works) and the build then succeeds with
   `-skipPackagePluginValidation`. Lesson: Metal-toolchain (and likely other
   `downloadComponent`) installs must be done by the user, not the agent.

So the canonical build command for this project is now:
`xcodebuild -project AIControl.xcodeproj -scheme AIControl -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation build`
(the unrelated CoreDevice/CoreSimulator plug-in warnings in the log are noise
from this machine's Xcode/OS mismatch and don't affect the build result).

## Deferred to Phase 5 (session management)
Awaiting-input detection (via the `dataReceived` tee or Claude Code hooks),
pinning running sessions on top, the Stop routine, Dock badge, notifications.
Phase 4 just proves: embed a PTY per project, send input, read output, and
keep the session alive across navigation. Auto-launching `claude` (vs. a plain
shell) is also left for later — Phase 4 gives a real shell the user can drive.
