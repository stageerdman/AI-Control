import Foundation
import AIControlCore

/// Keeps one `TerminalSession` per project URL alive for the app's lifetime, so
/// a project's shell **survives navigation** between the dashboard and the
/// project view (PROJECT.md §11). Sessions are created lazily on first open.
///
/// Phase 4 keeps this minimal — creation + reuse. Phase 5 (session management:
/// pinning running sessions on top, awaiting-input, the Stop routine) will
/// build the observable surface on top of what's stored here.
final class TerminalSessionStore: ObservableObject {
    private var sessions: [URL: TerminalSession] = [:]

    /// Returns the existing session for `url`, or creates and starts one.
    func session(for url: URL) -> TerminalSession {
        if let existing = sessions[url] { return existing }
        let session = TerminalSession(projectURL: url)
        sessions[url] = session
        return session
    }

    var activeSessions: [TerminalSession] { Array(sessions.values) }
}
