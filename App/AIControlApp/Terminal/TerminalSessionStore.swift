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
    /// Project URLs with a live session, so the dashboard can pin them on top
    /// and show a running indicator (PROJECT.md §8.1).
    @Published private(set) var runningURLs: Set<URL> = []

    private var sessions: [URL: TerminalSession] = [:]

    /// Returns the existing session for `url`, or creates and starts one.
    func session(for url: URL) -> TerminalSession {
        if let existing = sessions[url] { return existing }
        let session = TerminalSession(projectURL: url)
        session.onTerminated = { [weak self] endedURL in self?.handleTerminated(endedURL) }
        sessions[url] = session
        runningURLs.insert(url)
        return session
    }

    /// Right-click "Close Session": stops the process and drops the session so
    /// reopening the project starts a fresh one.
    func stopSession(for url: URL) {
        sessions[url]?.stop()
        // `stop()` fires onTerminated → handleTerminated does the cleanup, but
        // clear eagerly too so the UI updates immediately.
        sessions[url] = nil
        runningURLs.remove(url)
    }

    func isRunning(_ url: URL) -> Bool { runningURLs.contains(url) }

    private func handleTerminated(_ url: URL) {
        runningURLs.remove(url)
        sessions[url] = nil
    }
}
