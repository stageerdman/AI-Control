import Foundation

/// Runs read-only `git` commands in a folder and hands their output to
/// `GitStatusParser`. Deliberately thin: all interpretation lives in the
/// (unit-tested) parser, so the only untested surface here is the
/// process-spawning itself.
///
/// Never mutates the repo (`PROJECT.md` §12: the app does not run git that
/// changes state). If `git` is missing or the folder isn't a repo, returns
/// `.notARepository` rather than throwing.
public struct GitStatusReader {
    private let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    public func status(for folderURL: URL) -> GitStatus {
        // `rev-parse --is-inside-work-tree` is the cheap "is this a repo?" gate.
        guard let inside = run(["rev-parse", "--is-inside-work-tree"], in: folderURL),
              inside.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else {
            return .notARepository
        }

        let porcelain = run(["status", "--porcelain=v2", "--branch"], in: folderURL) ?? ""
        // Nul-separate fields so a subject containing spaces/newlines stays intact.
        let logLine = run(
            ["log", "-1", "--no-color", "--format=%h%x00%s%x00%cI"],
            in: folderURL
        ) ?? ""
        return GitStatusParser.parse(porcelain: porcelain, logLine: logLine)
    }

    /// Runs `git <args>` in `folderURL`, returning stdout, or `nil` on any
    /// failure (missing binary, non-zero exit, launch error).
    private func run(_ args: [String], in folderURL: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = folderURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
