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
final class TerminalSession: ObservableObject, LocalProcessTerminalViewDelegate {
    let projectURL: URL
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

    /// Sends Ctrl-C to interrupt whatever Claude Code (or the shell) is doing —
    /// the first step of the Stop routine (PROJECT.md §7/§9.7).
    func sendInterrupt() {
        terminalView.send(txt: "\u{03}") // ETX / Ctrl-C
    }

    /// Sends a full line of text (prompt + newline), e.g. the stop-routine prompt.
    func sendLine(_ text: String) {
        send(text + "\n")
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
                self?.send(command + "\n")
            }
        }
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
