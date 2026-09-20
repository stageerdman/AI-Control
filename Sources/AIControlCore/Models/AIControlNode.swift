import Foundation

/// Whether a folder is under AI Control, and how, per `PROJECT.md` §3.
public enum NodeKind: String, Equatable {
    case project
    case organizer
    case untouched
}

/// One folder found while scanning the root, classified per `PROJECT.md` §3.
/// Organizers carry their child projects in `children`; projects carry their
/// parsed `.project` file.
public struct AIControlNode: Identifiable, Equatable {
    public let url: URL
    public let kind: NodeKind
    public let projectFile: ProjectFile?
    public let children: [AIControlNode]

    /// True when this organizer's own children include another organizer.
    /// Nested organizers aren't allowed (`PROJECT.md` §3.2); the scanner still
    /// reports what it found instead of dropping or crashing on it, so the AI
    /// can be told to fix it.
    public let nestedOrganizerWarning: Bool

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(
        url: URL,
        kind: NodeKind,
        projectFile: ProjectFile? = nil,
        children: [AIControlNode] = [],
        nestedOrganizerWarning: Bool = false
    ) {
        self.url = url
        self.kind = kind
        self.projectFile = projectFile
        self.children = children
        self.nestedOrganizerWarning = nestedOrganizerWarning
    }
}
