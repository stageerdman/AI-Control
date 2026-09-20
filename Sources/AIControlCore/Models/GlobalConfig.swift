import Foundation

/// One global module file (`~/.ai-control/modules/UX.md`, `CODING.md`, ...).
/// The app never reads a module's *content* — only its identity and last
/// modification time, which is all CLAUDE.md drift detection needs (PROJECT.md
/// §6.2/§6.3). The AI authors and edits the content (principle 2/7).
public struct GlobalModule: Equatable {
    /// Bare module name without the `.md` extension, e.g. `UX`, `CODING`. This
    /// is what a project's `.project` `modules:` list refers to.
    public var name: String
    public var url: URL
    public var modifiedAt: Date

    public init(name: String, url: URL, modifiedAt: Date) {
        self.name = name
        self.url = url
        self.modifiedAt = modifiedAt
    }
}

/// One knowledge-wiki page (`~/.ai-control/wiki/GoHighLevel.md`, ...). Each page
/// carries a short **usage description** at the top so the wiki search script
/// and any AI can find it (PROJECT.md §6.4).
public struct WikiPage: Equatable {
    public var name: String
    public var url: URL
    /// The one-line usage description parsed from the top of the page, if any.
    public var usageDescription: String?

    public init(name: String, url: URL, usageDescription: String? = nil) {
        self.name = name
        self.url = url
        self.usageDescription = usageDescription
    }
}

/// A stored routine prompt (`~/.ai-control/prompts/<key>.md`). These are the
/// editable prompts the app's buttons send to Claude Code (PROJECT.md §8.6).
/// Keyed by a stable identifier (`stop`, `rebuild`, `sync`, ...).
public struct RoutinePrompt: Equatable {
    public var key: String
    public var url: URL
    public var text: String

    public init(key: String, url: URL, text: String) {
        self.key = key
        self.url = url
        self.text = text
    }
}

/// A read-only snapshot of the global configuration repo at `~/.ai-control/`
/// (PROJECT.md §6). Files are the only truth; this is just what the app read
/// off disk at scan time. `exists == false` means the repo hasn't been created.
public struct GlobalConfig: Equatable {
    /// The resolved root, e.g. `~/.ai-control/`.
    public var root: URL
    /// Whether the root directory actually exists on disk.
    public var exists: Bool
    public var modules: [GlobalModule]
    public var wikiPages: [WikiPage]
    public var prompts: [RoutinePrompt]
    /// Key *names* from the global `.env` — never values (PROJECT.md §6.5).
    public var secretNames: [String]

    public init(
        root: URL,
        exists: Bool = false,
        modules: [GlobalModule] = [],
        wikiPages: [WikiPage] = [],
        prompts: [RoutinePrompt] = [],
        secretNames: [String] = []
    ) {
        self.root = root
        self.exists = exists
        self.modules = modules
        self.wikiPages = wikiPages
        self.prompts = prompts
        self.secretNames = secretNames
    }

    /// Modules keyed by name, for drift lookups.
    public var moduleModifiedDates: [String: Date] {
        Dictionary(modules.map { ($0.name, $0.modifiedAt) }, uniquingKeysWith: { a, _ in a })
    }

    /// The stored text for a routine prompt key, if present.
    public func prompt(_ key: String) -> String? {
        prompts.first { $0.key == key }?.text
    }
}
