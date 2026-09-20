import Foundation

/// Coarse state of a project's Claude Code session, derived from Claude Code
/// hook events (`PROJECT.md` §7: running / awaiting-input). The app learns these
/// from per-project status files written by hooks — see `phase5-research.md`.
public enum SessionActivity: String, Equatable, Sendable {
    /// Claude is actively working (a prompt was just submitted, or the session
    /// just started).
    case working

    /// Claude finished responding and is **waiting for the user's next message**
    /// (or is asking for attention). This is what the dashboard highlights and
    /// what fires a notification / Dock badge.
    case awaitingInput

    /// The session ended (the CLI exited).
    case stopped

    /// An event we don't map to a specific state.
    case unknown

    /// Maps a raw Claude Code hook event name to a coarse activity. Centralizing
    /// this here (rather than in the shell hook) keeps the interpretation in the
    /// unit-tested layer; the hook script only needs to dump the event name.
    ///
    /// - `UserPromptSubmit`, `SessionStart` → `working`
    /// - `Stop`, `Notification` → `awaitingInput`
    /// - `SessionEnd` → `stopped`
    /// - anything else → `unknown`
    public init(hookEvent: String) {
        switch hookEvent {
        case "UserPromptSubmit", "SessionStart":
            self = .working
        case "Stop", "Notification":
            self = .awaitingInput
        case "SessionEnd":
            self = .stopped
        default:
            self = .unknown
        }
    }
}

/// One decoded session status file: which project folder it's for, the raw hook
/// event that produced it, and the activity that event maps to.
///
/// `cwd` is stored **exactly as the hook reported it** — Claude Code resolves
/// symlinks in the working directory (e.g. `/tmp` → `/private/tmp`, see
/// `phase5-research.md`), so callers matching a status back to a project URL
/// must canonicalize both sides (`URL.resolvingSymlinksInPath`) rather than
/// compare raw strings.
public struct SessionStatus: Equatable, Sendable {
    /// The session's working directory as reported by the hook (symlink-resolved).
    public var cwd: String

    /// The raw Claude Code hook event name (`Stop`, `UserPromptSubmit`, …).
    public var event: String

    /// Claude Code's session id, if present.
    public var sessionID: String?

    /// The coarse activity `event` maps to.
    public var activity: SessionActivity { SessionActivity(hookEvent: event) }

    public init(cwd: String, event: String, sessionID: String? = nil) {
        self.cwd = cwd
        self.event = event
        self.sessionID = sessionID
    }
}
