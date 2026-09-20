import Foundation
import CryptoKit
import AIControlCore

/// Owns the on-disk machinery that lets the app observe Claude Code session
/// state (PROJECT.md §7, §11) — validated in `phase5-experiment/` /
/// `phase5-research.md`. For each project it launches, the app hands Claude Code
/// an app-owned `--settings` file that (a) turns on `bypassPermissions` (auto
/// mode, §4) and (b) registers hooks that write a tiny per-project **status
/// file** the app watches.
///
/// Everything lives under Application Support, never in the user's own
/// `~/.claude/settings.json`. The hook is a shipped shell script that receives
/// the event name, the output path, and the project path as **arguments** — so
/// it needs no JSON parser (no `jq`/`python` dependency) and can't be broken by
/// hook-payload changes.
struct SessionHooks {
    let appDirectory: URL
    let scriptURL: URL
    let statusDirectory: URL
    let settingsDirectory: URL

    /// The hook events we register. `Stop`/`Notification` are the awaiting-input
    /// signals (Claude finished, or it's asking a question / idle-prompting);
    /// `UserPromptSubmit`/`SessionStart` mean working; `SessionEnd` means the CLI
    /// exited. `SessionStatusParser` maps these to `SessionActivity`. `Stop` and
    /// `Notification` are the ones proven to need a `"*"` matcher (see
    /// `phase5-research.md`).
    static let events = ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "SessionEnd"]
    private static let matchedEvents: Set<String> = ["Stop", "Notification"]

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        appDirectory = base.appendingPathComponent("AIControl", isDirectory: true)
        scriptURL = appDirectory.appendingPathComponent("status-hook.sh")
        statusDirectory = appDirectory.appendingPathComponent("status", isDirectory: true)
        settingsDirectory = appDirectory.appendingPathComponent("settings", isDirectory: true)
    }

    /// Creates the directories, writes (or refreshes) the hook script, and clears
    /// any stale status files from a previous run so nothing matches a session
    /// that no longer exists. Idempotent — safe to call on every launch.
    func install(fileManager: FileManager = .default) {
        for dir in [appDirectory, statusDirectory, settingsDirectory] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? hookScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Drop stale status files from a prior run.
        if let stale = try? fileManager.contentsOfDirectory(at: statusDirectory, includingPropertiesForKeys: nil) {
            for file in stale { try? fileManager.removeItem(at: file) }
        }
    }

    /// Stable, filesystem-safe key for a project — SHA-1 of its **canonical**
    /// (symlink-resolved) path, since Claude Code reports a resolved `cwd`.
    func key(for projectURL: URL) -> String {
        let path = projectURL.resolvingSymlinksInPath().path
        let digest = Insecure.SHA1.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func statusFileURL(for projectURL: URL) -> URL {
        statusDirectory.appendingPathComponent("\(key(for: projectURL)).json")
    }

    /// Writes the per-project Claude Code settings file and returns its URL. The
    /// hooks bake in this project's status-file path and canonical cwd, so the
    /// shell hook is a trivial no-parse writer.
    @discardableResult
    func writeSettings(for projectURL: URL) -> URL {
        let settingsURL = settingsDirectory.appendingPathComponent("\(key(for: projectURL)).json")
        try? settingsJSON(for: projectURL).write(to: settingsURL, atomically: true, encoding: .utf8)
        return settingsURL
    }

    /// Removes a project's status file (on session close), so it can't linger and
    /// re-mark a stopped project as awaiting input.
    func removeStatus(for projectURL: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: statusFileURL(for: projectURL))
    }

    /// The command to auto-run in the project's shell: launch Claude Code with
    /// the app-owned settings file (for the state hooks) and
    /// `--dangerously-skip-permissions` for auto mode (§4, §11). The flag — not
    /// the settings file — is what actually skips the gates **interactively**:
    /// `permissions.defaultMode: bypassPermissions` from `--settings` still pops
    /// a one-time "Yes, I accept" bypass screen and a folder-trust prompt in the
    /// TUI, whereas the flag starts clean (verified during Phase 5 debugging —
    /// see `phase5-research.md`). Paths are double-quoted because Application
    /// Support contains a space.
    func autoLaunchCommand(for projectURL: URL) -> String {
        let settingsURL = writeSettings(for: projectURL)
        return "claude --settings \"\(settingsURL.path)\" --dangerously-skip-permissions"
    }

    // MARK: - Generated file contents

    /// `status-hook.sh <event> <statusFile> <cwd>` — writes `{cwd,event}` to
    /// `statusFile` atomically (temp + mv), so the watcher never reads a partial
    /// file. No stdin, no JSON parser.
    private var hookScript: String {
        """
        #!/bin/sh
        # Generated by AI Control (Phase 5). Records a Claude Code session's
        # state so the app can show awaiting-input / running. Args:
        #   $1 = hook event name   $2 = output status file   $3 = project cwd
        event="$1"
        out="$2"
        cwd="$3"
        [ -z "$out" ] && exit 0
        tmp="$out.tmp.$$"
        printf '{"cwd":"%s","event":"%s"}\\n' "$cwd" "$event" > "$tmp" && mv "$tmp" "$out"
        exit 0
        """
    }

    private func settingsJSON(for projectURL: URL) -> String {
        let cwd = projectURL.resolvingSymlinksInPath().path
        let out = statusFileURL(for: projectURL).path
        // Each event registers the same script with the event name baked in as
        // an argument. Command + args are quoted so the space in Application
        // Support doesn't get word-split by /bin/sh.
        let hookEntries = Self.events.map { event in
            let command = "\"\(scriptURL.path)\" \(event) \"\(out)\" \"\(cwd)\""
            let matcher = Self.matchedEvents.contains(event) ? #""matcher": "*", "# : ""
            return """
                "\(event)": [
                  { \(matcher)"hooks": [ { "type": "command", "command": "\(escaped(command))" } ] }
                ]
            """
        }.joined(separator: ",\n")

        // No "permissions" block here — auto mode comes from the
        // --dangerously-skip-permissions launch flag, which (unlike a
        // bypassPermissions defaultMode in settings) doesn't pop an acceptance
        // screen in the interactive TUI.
        return """
        {
          "hooks": {
        \(hookEntries)
          }
        }
        """
    }

    /// Escapes a shell command string for embedding inside a JSON string literal.
    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
