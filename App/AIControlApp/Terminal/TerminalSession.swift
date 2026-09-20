import Foundation
import SwiftTerm

/// A `LocalProcessTerminalView` that tees the raw process→terminal bytes to a
/// callback before rendering them, so higher layers can observe output (Phase 5
/// will use this for idle / awaiting-input detection). Overriding `dataReceived`
/// is the supported hook — see `phase4-research.md`.
final class TeeingTerminalView: LocalProcessTerminalView {
    var onData: ((ArraySlice<UInt8>) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onData?(slice)
        super.dataReceived(slice: slice)
    }
}

/// One embedded Claude Code / shell session for a single project, wrapping a
/// SwiftTerm PTY view. Owns the terminal view (so it survives navigation
/// between the dashboard and the project view), launches a login shell in the
/// project folder, and exposes the two capabilities PROJECT.md §11 requires:
/// **send input** (`send(_:)`) and **read output** (`recentOutput` / the tee).
final class TerminalSession: ObservableObject, LocalProcessTerminalViewDelegate, Identifiable {
    let projectURL: URL
    var id: URL { projectURL }
    let terminalView: TeeingTerminalView

    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?

    /// Command auto-run once the shell is ready, so opening a project drops you
    /// straight into Claude Code (PROJECT.md §7/§8.3). `nil` leaves a plain
    /// shell. Set by the store to `claude --settings <app file>`, which turns on
    /// bypassPermissions (auto mode, §4) and registers the state hooks (§11).
    var autoLaunchCommand: String?

    /// Called when the session ends (process exits or `stop()`), on the main
    /// thread — the store uses it to drop the session and clear its pin.
    var onTerminated: ((URL) -> Void)?

    /// Bounded rolling tail of recent output, kept for later idle/awaiting-input
    /// detection (Phase 5). Not the full scrollback — just enough to reason
    /// about the current prompt state.
    private(set) var recentOutput = ""
    private let recentLimit = 8192
    private var didAutoLaunch = false

    /// Fired once, on the main thread, when the session first looks ready for
    /// programmatic input: the auto-launched command was sent and output has gone
    /// quiet (Claude's TUI finished booting), or a hard cap elapsed. Lets callers
    /// time a first prompt into a freshly-opened session (e.g. the module-authoring
    /// interview) without racing Claude's startup — a fixed delay can't, since a
    /// cold session hasn't even launched Claude yet.
    var onReady: (() -> Void)?
    private var autoLaunchSent = false
    private var didFireReady = false
    private var readyTimer: DispatchWorkItem?

    init(projectURL: URL, autoLaunchCommand: String? = "claude") {
        self.projectURL = projectURL
        self.autoLaunchCommand = autoLaunchCommand
        terminalView = TeeingTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 480))
        terminalView.processDelegate = self
        terminalView.onData = { [weak self] slice in self?.handleData(slice) }
        start()
    }

    /// Launches the user's **login** shell (`-l`) so it sources the profile and
    /// sets `PATH` — SwiftTerm's default environment omits `PATH`, so a bare
    /// shell wouldn't find `git`/`gh`/`claude` (see `phase4-research.md`).
    func start() {
        guard !isRunning else { return }
        didAutoLaunch = false
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: nil,
            currentDirectory: projectURL.path
        )
        isRunning = true
        exitCode = nil
    }

    /// Sends text to the child process as if typed (prompts, interrupts, exit).
    func send(_ text: String) {
        terminalView.send(txt: text)
    }

    /// Interrupts whatever Claude Code is doing — the first step of the Stop
    /// routine (PROJECT.md §7/§9.7). Claude Code interrupts on **Esc** (Ctrl-C is
    /// its *exit* key), and pressing Esc at an idle/question prompt harmlessly
    /// clears the input line, so this is safe whether or not a task is running.
    func sendInterrupt() {
        terminalView.send(txt: "\u{1b}") // ESC
    }

    /// Types `text`, then presses Enter as a **separate** keystroke shortly
    /// after. Two reasons this can't be one `send(text + "\r")`:
    /// 1. Enter in Claude's raw-mode TUI is a carriage return (`\r`), not `\n`.
    /// 2. Claude's TUI does **paste detection** — a long string arriving in one
    ///    burst is treated as a paste, and a `\r` at its tail is kept as a
    ///    literal newline instead of submitting. Sending the `\r` on its own,
    ///    after the paste window closes, makes it a real Enter keypress.
    /// `\r` also submits in the cooked-mode shell (the tty maps CR→NL), so this
    /// is correct for both the shell and the Claude TUI.
    func sendLine(_ text: String) {
        send(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.send("\r")
        }
    }

    /// Asks the CLI to exit cleanly (`/exit`), used at the end of the Stop
    /// routine once Claude has finished wrapping up.
    func sendExit() {
        sendLine("/exit")
    }

    /// Terminates the child process (the right-click "Close Session" action).
    func stop() {
        guard isRunning else { return }
        terminalView.terminate()
        isRunning = false
        onTerminated?(projectURL)
    }

    private func handleData(_ slice: ArraySlice<UInt8>) {
        appendRecent(slice)
        // Auto-run Claude once, after the shell has emitted its first output
        // (i.e. it's initialized and ready for input). A brief hop avoids
        // racing the shell's line editor on that very first prompt.
        if !didAutoLaunch, let command = autoLaunchCommand {
            didAutoLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                self.send(command + "\r") // CR submits in both the shell and Claude's TUI
                self.autoLaunchSent = true
                // Hard cap: fire ready even if output never fully quiesces.
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.fireReady() }
            }
        }
        // After launch, treat 1.6s of output silence as "booted and idle at the
        // prompt" and fire ready then. Each new byte pushes the deadline out.
        if autoLaunchSent && !didFireReady { bumpReadyQuiescence() }
    }

    /// (Re)arms the quiescence timer; when it fires without being pushed again,
    /// output has been quiet long enough to call the session ready.
    private func bumpReadyQuiescence() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.autoLaunchSent, !self.didFireReady else { return }
            self.readyTimer?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.fireReady() }
            self.readyTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
    }

    private func fireReady() {
        guard !didFireReady else { return }
        didFireReady = true
        readyTimer?.cancel()
        onReady?()
    }

    private func appendRecent(_ slice: ArraySlice<UInt8>) {
        guard let chunk = String(bytes: slice, encoding: .utf8) else { return }
        recentOutput += chunk
        if recentOutput.count > recentLimit {
            recentOutput = String(recentOutput.suffix(recentLimit))
        }
    }

    // MARK: - LocalProcessTerminalViewDelegate
    // SwiftTerm may deliver these off the main thread; hop to main for @Published.

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            guard self.isRunning else { return }
            self.isRunning = false
            self.exitCode = exitCode
            self.onTerminated?(self.projectURL)
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
