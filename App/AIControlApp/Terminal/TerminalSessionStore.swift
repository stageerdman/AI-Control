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

    /// Source of the editable routine prompts (`~/.ai-control/prompts/`). Set by
    /// the view after construction. Prompts fall back to their built-in defaults
    /// when this is absent or the repo isn't set up, so behavior is unchanged
    /// before the global config exists.
    weak var globalConfig: GlobalConfigStore?

    /// In-flight graceful Stop routines, keyed by project URL. See
    /// `runStopRoutine(for:)`.
    private var stopping: [URL: StopState] = [:]

    /// Projects with a Rebuild-CLAUDE.md prompt in flight, surfaced by the
    /// sidebar as a "Rebuilding…" line (PROJECT.md §6.3). Cleared once Claude
    /// finishes (working→awaiting) so the `.project` re-read can self-heal drift.
    @Published private(set) var rebuildingURLs: Set<URL> = []
    private var rebuilding: [URL: RebuildState] = [:]

    /// The prompt sent to Claude Code during the graceful Stop routine
    /// (PROJECT.md §7/§9.7), resolved from the global prompt store with a
    /// built-in default fallback.
    private var stopRoutinePrompt: String {
        globalConfig?.promptText(for: .stop) ?? RoutinePromptKind.stop.defaultText
    }

    /// Tracks one graceful stop: whether we've seen Claude start working on the
    /// wrap-up prompt yet (so a pre-existing idle state doesn't trigger an early
    /// exit).
    private struct StopState {
        var sawWorking = false
    }

    /// Tracks one in-flight Rebuild: whether Claude has started working on the
    /// prompt yet, so a pre-existing idle state doesn't clear it immediately.
    private struct RebuildState {
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

    // MARK: - Rebuild CLAUDE.md (PROJECT.md §6.3)

    /// Sends the Rebuild-CLAUDE.md routine prompt into the project's own session,
    /// starting one if needed. The app never edits CLAUDE.md itself — the AI does
    /// (principle 2). Marks the project as rebuilding for the sidebar until Claude
    /// finishes; the resulting `.project` rewrite is what actually clears drift.
    /// `appendix` carries any extra context to include after the base prompt.
    func rebuildClaudeMd(for url: URL, appendix: String = "") {
        let session = session(for: url) // starts one if absent (same path as open)
        rebuilding[url] = RebuildState()
        rebuildingURLs.insert(url)

        let base = globalConfig?.promptText(for: .rebuildClaudeMd) ?? RoutinePromptKind.rebuildClaudeMd.defaultText
        let prompt = appendix.isEmpty ? base : base + "\n\n" + appendix
        // Small delay so a freshly-launched session's `claude` is ready at its
        // input line before we type (mirrors the Stop routine's settle beat).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.rebuilding[url] != nil else { return }
            session.sendLine(prompt)
        }
    }

    /// Whether a Rebuild prompt is currently in flight for `url`.
    func isRebuilding(_ url: URL) -> Bool { rebuilding[url] != nil }

    /// Starts (or reuses) a Claude session at `dir` and — only if it's freshly
    /// started — sends the author-modules interview prompt (PROJECT.md §6.2,
    /// Option C). Returns the session so the caller can present its terminal for
    /// the interview. The AI writes the module files; the app writes nothing.
    @discardableResult
    func authorModules(at dir: URL) -> TerminalSession {
        let isNew = sessions[dir] == nil
        let session = session(for: dir)
        if isNew {
            let prompt = globalConfig?.promptText(for: .authorModules) ?? RoutinePromptKind.authorModules.defaultText
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { session.sendLine(prompt) }
        }
        return session
    }

    /// Advances an in-flight Rebuild: once Claude has picked up the prompt
    /// (`working`) and then returns to `awaitingInput`, it's done — clear the
    /// flag so the drift row can self-heal from the rewritten `.project`.
    private func advanceRebuild(_ url: URL, activity: SessionActivity) {
        guard var state = rebuilding[url] else { return }
        switch activity {
        case .working:
            if !state.sawWorking { state.sawWorking = true; rebuilding[url] = state }
        case .awaitingInput where state.sawWorking, .stopped:
            rebuilding[url] = nil
            rebuildingURLs.remove(url)
        default:
            break
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
            advanceRebuild(url, activity: status.activity)
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
        rebuilding[url] = nil
        rebuildingURLs.remove(url)
        keyToURL[hooks.key(for: url)] = nil
        runningURLs.remove(url)
        hooks.removeStatus(for: url)
        recomputeAwaitingInput()
    }
}
