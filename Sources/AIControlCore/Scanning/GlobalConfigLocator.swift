import Foundation

/// Resolves where the global configuration repo lives (PROJECT.md §6). Defaults
/// to `~/.ai-control/`; the `AI_CONTROL_HOME` environment variable overrides it,
/// which lets tests point at a temp directory without touching the real one.
public enum GlobalConfigLocator {
    public static let subdirectories = (
        modules: "modules",
        wiki: "wiki",
        prompts: "prompts"
    )
    public static let envFileName = ".env"

    /// The resolved root directory. Not guaranteed to exist.
    public static func rootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["AI_CONTROL_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).resolvingSymlinksInPath()
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ai-control", isDirectory: true).resolvingSymlinksInPath()
    }
}
