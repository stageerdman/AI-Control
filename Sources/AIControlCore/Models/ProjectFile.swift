import Foundation

/// The parsed contents of a `.project` marker file: frontmatter fields from
/// `PROJECT.md` §4 plus the free-text body (description, how-to-use, status).
public struct ProjectFile: Equatable {
    public var name: String?
    public var github: String?
    public var visibility: String?
    public var adopted: String?
    public var claudeMdGenerated: String?
    public var modules: [String]
    public var secrets: [String]
    public var body: String

    public init(
        name: String? = nil,
        github: String? = nil,
        visibility: String? = nil,
        adopted: String? = nil,
        claudeMdGenerated: String? = nil,
        modules: [String] = [],
        secrets: [String] = [],
        body: String = ""
    ) {
        self.name = name
        self.github = github
        self.visibility = visibility
        self.adopted = adopted
        self.claudeMdGenerated = claudeMdGenerated
        self.modules = modules
        self.secrets = secrets
        self.body = body
    }
}
