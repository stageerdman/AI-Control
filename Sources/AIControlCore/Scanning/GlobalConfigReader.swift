import Foundation

/// Reads the global configuration repo (`~/.ai-control/`) off disk into a
/// `GlobalConfig` snapshot (PROJECT.md §6). Read-only: it never writes or edits
/// anything (the AI authors module/wiki content; the app only reads it). Missing
/// pieces degrade gracefully to empty — a partially-set-up repo is normal.
public struct GlobalConfigReader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Reads the config at the resolved root (or an explicit `root`, for tests).
    public func read(root: URL = GlobalConfigLocator.rootURL()) -> GlobalConfig {
        var config = GlobalConfig(root: root)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return config // exists == false
        }
        config.exists = true

        config.modules = readModules(in: root.appendingPathComponent(GlobalConfigLocator.subdirectories.modules, isDirectory: true))
        config.wikiPages = readWikiPages(in: root.appendingPathComponent(GlobalConfigLocator.subdirectories.wiki, isDirectory: true))
        config.prompts = readPrompts(in: root.appendingPathComponent(GlobalConfigLocator.subdirectories.prompts, isDirectory: true))
        config.secretNames = readSecretNames(at: root.appendingPathComponent(GlobalConfigLocator.envFileName, isDirectory: false))

        return config
    }

    // MARK: - Modules

    private func readModules(in dir: URL) -> [GlobalModule] {
        markdownFiles(in: dir).compactMap { url in
            guard let modifiedAt = modificationDate(of: url) else { return nil }
            return GlobalModule(name: baseName(url), url: url, modifiedAt: modifiedAt)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Wiki

    private func readWikiPages(in dir: URL) -> [WikiPage] {
        markdownFiles(in: dir).map { url in
            let contents = try? String(contentsOf: url, encoding: .utf8)
            return WikiPage(
                name: baseName(url),
                url: url,
                usageDescription: contents.flatMap(Self.usageDescription(from:))
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The usage description a wiki page carries at its top (PROJECT.md §6.4):
    /// the first non-blank line that isn't a markdown heading.
    static func usageDescription(from contents: String) -> String? {
        for rawLine in contents.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            return line
        }
        return nil
    }

    // MARK: - Prompts

    private func readPrompts(in dir: URL) -> [RoutinePrompt] {
        markdownFiles(in: dir).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return RoutinePrompt(
                key: baseName(url),
                url: url,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    // MARK: - Secrets (names only)

    /// Parses `.env` for key **names** only — values are never read into memory
    /// beyond the split, and never stored (PROJECT.md §6.5).
    private func readSecretNames(at url: URL) -> [String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        for rawLine in contents.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(key)
        }
        return names
    }

    // MARK: - Helpers

    private func markdownFiles(in dir: URL) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { $0.pathExtension.lowercased() == "md" }
    }

    private func baseName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
