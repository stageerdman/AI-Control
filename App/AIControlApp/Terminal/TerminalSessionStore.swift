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

    /// In-flight graceful Stop routines, keyed by project URL. See
    /// `runStopRoutine(for:)`.
    private var stopping: [URL: StopState] = [:]

    /// The prompt sent to Claude Code during the graceful Stop routine
    /// (PROJECT.md §7/§9.7). Hardcoded for now; the Settings window (§8.6,
    /// Phase 9) will make it editable — same seam as `autoLaunchCommand`.
    var stopRoutinePrompt =
        "Please wrap up now: bring the current task to a safe stopping point, " +
        "save any state and notes so we can continue later, update the relevant " +
        "tracking files, then commit and push everything. We'll come back to this."

    /// Tracks one graceful stop: whether we've seen Claude start working on the
    /// wrap-up prompt yet (so a pre-existing idle state doesn't trigger an early
    /// exit).
    private struct StopState {
        var sawWorking = false
    }

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

    func isStopping(_ url: URL) -> Bool { stopping[url] != nil }

    func activity(for url: URL) -> SessionActivity {
        activityByURL[url] ?? .working
    }

    // MARK: - Graceful Stop routine (PROJECT.md §7/§9.7)

    /// Right-click "Stop": interrupt whatever Claude is doing, ask it to wrap up
    /// (save state, commit, push), wait until it's finished (the `Stop` hook),
    /// then exit the CLI and close the session. Distinct from "Force Close"
    /// (`stopSession`), which kills it immediately. A hard timeout guarantees the
    /// session is closed even if the wrap-up never signals completion.
    func runStopRoutine(for url: URL) {
        guard let session = sessions[url], stopping[url] == nil else { return }
        stopping[url] = StopState()

        session.sendInterrupt()
        // Give the interrupt a beat to actually halt generation and return Claude
        // to a ready input line before typing, so no keystrokes are dropped
        // mid-interrupt. Works the same whether Claude was mid-task or waiting on
        // a question (Esc cancels either).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.stopping[url] != nil else { return }
            session.sendLine(self.stopRoutinePrompt)
        }

        // Safety net: if the wrap-up never reports completion, force-close so a
        // "Stop" can't hang a session forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self, self.stopping[url] != nil else { return }
            self.finishStop(url)
        }
    }

    /// Advances an in-flight Stop routine based on the latest activity. Called
    /// from `refreshActivity`. We require having seen `working` (Claude picking
    /// up the wrap-up prompt) before treating a later `awaitingInput` as "wrap-up
    /// done" — otherwise a pre-existing idle state would exit immediately.
    private func advanceStopRoutine(_ url: URL, activity: SessionActivity) {
        guard var state = stopping[url] else { return }
        switch activity {
        case .working:
            if !state.sawWorking { state.sawWorking = true; stopping[url] = state }
        case .awaitingInput where state.sawWorking:
            finishStop(url)
        case .stopped:
            finishStop(url)
        default:
            break
        }
    }

    /// Wrap-up is done (or timed out): exit the CLI cleanly, then close the
    /// session shortly after so it unpins from the dashboard.
    private func finishStop(_ url: URL) {
        guard stopping[url] != nil else { return }
        stopping[url] = nil
        sessions[url]?.sendExit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopSession(for: url)
        }
    }

    // MARK: - Status watching

    /// Re-reads every tracked project's status file and republishes activity.
    /// Called on the main queue by the directory watcher.
    private func refreshActivity() {
        for (_, url) in keyToURL {
            guard let status = SessionStatusParser.parse(contentsOf: hooks.statusFileURL(for: url)) else { continue }
            activityByURL[url] = status.activity
            advanceStopRoutine(url, activity: status.activity)
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
        stopping[url] = nil
        keyToURL[hooks.key(for: url)] = nil
        runningURLs.remove(url)
        hooks.removeStatus(for: url)
        recomputeAwaitingInput()
    }
}
