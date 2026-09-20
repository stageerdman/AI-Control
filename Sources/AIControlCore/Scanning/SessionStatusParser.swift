import Foundation

/// Turns the JSON in one session status file into a `SessionStatus`. Pure and
/// I/O-free so it can be unit-tested exhaustively; the app's status-directory
/// watcher (App target) is the thin layer that reads files and feeds this.
///
/// The file is written by a Claude Code hook (see `phase5-research.md`) and
/// carries the hook's `cwd` and event name. We accept both our own compact key
/// (`event`) and Claude Code's native field (`hook_event_name`) so the same
/// parser works whether the hook forwards the raw stdin payload or a trimmed
/// version.
public enum SessionStatusParser {
    /// Returns a `SessionStatus`, or `nil` when the data isn't valid JSON, isn't
    /// an object, or is missing the fields we need (`cwd` and an event name).
    public static func parse(_ data: Data) -> SessionStatus? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else { return nil }

        guard let cwd = string(dict["cwd"]), !cwd.isEmpty else { return nil }

        // Prefer our compact `event`; fall back to Claude Code's native key.
        guard let event = string(dict["event"]) ?? string(dict["hook_event_name"]),
              !event.isEmpty
        else { return nil }

        let session = string(dict["session"]) ?? string(dict["session_id"])
        return SessionStatus(cwd: cwd, event: event, sessionID: session)
    }

    /// Convenience for reading a status file directly from disk.
    public static func parse(contentsOf url: URL) -> SessionStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}
