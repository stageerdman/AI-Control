import Foundation

/// Read-only snapshot of a folder's git state, for the project sidebar
/// (`PROJECT.md` §8.2, §10). The app never mutates git — it only reports what
/// the working tree looks like so the sidebar can show branch, sync state, and
/// the last commit.
public struct GitStatus: Equatable {
    /// False when the folder isn't a git working tree at all (no repo).
    public var isRepository: Bool

    /// Current branch name, or `nil` when the head is detached.
    public var branch: String?

    /// Configured upstream for the current branch (e.g. `origin/main`), if any.
    public var upstream: String?

    /// Commits the local branch is ahead of its upstream (unpushed).
    public var ahead: Int

    /// Commits the local branch is behind its upstream (unpulled).
    public var behind: Int

    /// Number of changed entries in the working tree: staged, unstaged, and
    /// untracked files all count. Zero means a clean tree.
    public var changedFileCount: Int

    /// Short hash of the most recent commit, if the repo has any commits.
    public var lastCommitHash: String?

    /// Subject line of the most recent commit.
    public var lastCommitSubject: String?

    /// Author/commit date of the most recent commit.
    public var lastCommitDate: Date?

    public var hasUncommittedChanges: Bool { changedFileCount > 0 }
    public var isClean: Bool { isRepository && changedFileCount == 0 }
    public var hasUpstream: Bool { upstream != nil }

    public static let notARepository = GitStatus(isRepository: false)

    public init(
        isRepository: Bool,
        branch: String? = nil,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        changedFileCount: Int = 0,
        lastCommitHash: String? = nil,
        lastCommitSubject: String? = nil,
        lastCommitDate: Date? = nil
    ) {
        self.isRepository = isRepository
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changedFileCount = changedFileCount
        self.lastCommitHash = lastCommitHash
        self.lastCommitSubject = lastCommitSubject
        self.lastCommitDate = lastCommitDate
    }
}
