import Foundation

/// Turns raw `git` output into a `GitStatus`. Kept pure and free of any
/// process spawning so it can be unit-tested exhaustively; `GitStatusReader`
/// is the thin layer that actually runs `git` and feeds this parser.
///
/// Expects the output of `git status --porcelain=v2 --branch` plus a
/// nul-separated one-line `git log` (`%h`, `%s`, `%cI`), which `GitStatusReader`
/// produces.
public enum GitStatusParser {
    /// ISO 8601 with fractional-second tolerance off — `%cI` emits strict
    /// RFC 3339 (e.g. `2026-09-20T12:04:11+02:00`).
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `porcelain`: stdout of `git status --porcelain=v2 --branch`.
    /// `logLine`: stdout of the one-line nul-separated `git log`, or empty when
    /// the repo has no commits yet.
    public static func parse(porcelain: String, logLine: String) -> GitStatus {
        var status = GitStatus(isRepository: true)
        var changedCount = 0

        for rawLine in porcelain.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)

            if line.hasPrefix("# branch.head ") {
                let value = dropPrefix(line, "# branch.head ")
                status.branch = value == "(detached)" ? nil : value
            } else if line.hasPrefix("# branch.upstream ") {
                let value = dropPrefix(line, "# branch.upstream ")
                status.upstream = value.isEmpty ? nil : value
            } else if line.hasPrefix("# branch.ab ") {
                let (ahead, behind) = parseAheadBehind(dropPrefix(line, "# branch.ab "))
                status.ahead = ahead
                status.behind = behind
            } else if line.hasPrefix("#") {
                continue // other header lines (branch.oid) — not needed
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") || line.hasPrefix("? ") {
                // Changed (1), renamed/copied (2), unmerged (u), untracked (?).
                // Ignored (! ) never appears without --ignored, so anything
                // that reaches here is a real working-tree change.
                changedCount += 1
            }
        }

        status.changedFileCount = changedCount
        applyLastCommit(logLine, to: &status)
        return status
    }

    private static func applyLastCommit(_ logLine: String, to status: inout GitStatus) {
        let trimmed = logLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parts = trimmed.components(separatedBy: "\u{0}")
        guard parts.count >= 2 else { return }

        status.lastCommitHash = parts[0].isEmpty ? nil : parts[0]
        status.lastCommitSubject = parts[1]
        if parts.count >= 3 {
            status.lastCommitDate = isoFormatter.date(from: parts[2].trimmingCharacters(in: .whitespaces))
        }
    }

    private static func parseAheadBehind(_ value: String) -> (Int, Int) {
        var ahead = 0
        var behind = 0
        for token in value.split(separator: " ") {
            if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
            else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
        }
        return (ahead, behind)
    }

    private static func dropPrefix(_ line: String, _ prefix: String) -> String {
        String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
