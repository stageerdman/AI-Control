import Foundation
import AIControlCore

/// Keeps one `TerminalSession` per project URL alive for the app's lifetime, so
/// a project's shell **survives navigation** between the dashboard and the
/// project view (PROJECT.md §11). Sessions are created lazily on first open.
///
/// Also the app's window onto **session state** (§7): it launches each session's
/// `claude` with the app-owned hooks/settings file (`SessionHooks`), watches the
/// status directory those hooks write to, and publishes which projects are
/// **running** and which are **awaiting input**.
final class TerminalSessionStore: ObservableObject {
    /// Project URLs with a live session, so the dashboard can pin them on top
    /// and show a running indicator (PROJECT.md §8.1).
    @Published private(set) var runningURLs: Set<URL> = []

    /// Project URLs whose session has finished responding and is waiting for the
    /// user (PROJECT.md §7/§8.1) — drives the highlight, notification, and Dock
    /// badge.
    @Published private(set) var awaitingInputURLs: Set<URL> = []

    private var sessions: [URL: TerminalSession] = [:]
    private var activityByURL: [URL: SessionActivity] = [:]
    /// SHA-1 key → project URL, so a status file (named by key) maps back to its
    /// project without re-resolving paths on every file event.
    private var keyToURL: [String: URL] = [:]

    private let hooks = SessionHooks()
    private var watcher: StatusDirectoryWatcher?

    init() {
        hooks.install()
        watcher = StatusDirectoryWatcher(directory: hooks.statusDirectory) { [weak self] in
            self?.refreshActivity()
        }
    }

    /// Returns the existing session for `url`, or creates and starts one — with
    /// Claude Code launched under the app's hooks/bypass settings.
    func session(for url: URL) -> TerminalSession {
        if let existing = sessions[url] { return existing }
        let session = TerminalSession(projectURL: url, autoLaunchCommand: hooks.autoLaunchCommand(for: url))
        session.onTerminated = { [weak self] endedURL in self?.handleTerminated(endedURL) }
        sessions[url] = session
        keyToURL[hooks.key(for: url)] = url
        runningURLs.insert(url)
        return session
    }

    /// Right-click "Force Close": stops the process immediately and drops the
    /// session so reopening the project starts a fresh one. The graceful Stop
    /// routine is `runStopRoutine(for:)`.
    func stopSession(for url: URL) {
        sessions[url]?.stop()
        // `stop()` fires onTerminated → handleTerminated does the cleanup, but
        // clear eagerly too so the UI updates immediately.
        cleanup(url)
    }

    func isRunning(_ url: URL) -> Bool { runningURLs.contains(url) }

    func activity(for url: URL) -> SessionActivity {
        activityByURL[url] ?? .working
    }

    // MARK: - Status watching

    /// Re-reads every tracked project's status file and republishes activity.
    /// Called on the main queue by the directory watcher.
    private func refreshActivity() {
        for (_, url) in keyToURL {
            guard let status = SessionStatusParser.parse(contentsOf: hooks.statusFileURL(for: url)) else { continue }
            activityByURL[url] = status.activity
        }
        recomputeAwaitingInput()
    }

    private func recomputeAwaitingInput() {
        let awaiting = Set(runningURLs.filter { activityByURL[$0] == .awaitingInput })
        if awaiting != awaitingInputURLs { awaitingInputURLs = awaiting }
    }

    // MARK: - Lifecycle cleanup

    private func handleTerminated(_ url: URL) {
        cleanup(url)
    }

    private func cleanup(_ url: URL) {
        sessions[url] = nil
        activityByURL[url] = nil
        keyToURL[hooks.key(for: url)] = nil
        runningURLs.remove(url)
        hooks.removeStatus(for: url)
        recomputeAwaitingInput()
    }
}
