import Foundation

/// Persists the connected root folder and which organizers are expanded,
/// across launches, via `UserDefaults`. The app isn't sandboxed, so a plain
/// stored path is enough — no security-scoped bookmarks needed.
final class RootFolderStore: ObservableObject {
    private enum Keys {
        static let rootPath = "rootFolderPath"
        static let expandedPaths = "expandedOrganizerPaths"
    }

    private let defaults: UserDefaults

    @Published var rootURL: URL? {
        didSet { defaults.set(rootURL?.path, forKey: Keys.rootPath) }
    }

    @Published var expandedIDs: Set<URL> {
        didSet { defaults.set(expandedIDs.map(\.path), forKey: Keys.expandedPaths) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Keys.rootPath) {
            rootURL = URL(fileURLWithPath: path)
        } else {
            rootURL = nil
        }
        let expandedPaths = defaults.stringArray(forKey: Keys.expandedPaths) ?? []
        expandedIDs = Set(expandedPaths.map { URL(fileURLWithPath: $0) })
    }
}
