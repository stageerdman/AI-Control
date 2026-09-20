import Foundation

/// Classifies a root folder's contents per `PROJECT.md` §3: a folder is a
/// project (has `.project`), an organizer (has `.organize`, and holds
/// project folders), or untouched (neither).
public struct FolderScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scans the root's immediate children. Organizers are expanded one
    /// level deeper to list their projects; nested organizers aren't
    /// recursed into further (`PROJECT.md` §3.2), but are reported via
    /// `nestedOrganizerWarning` on the parent organizer.
    public func scanRoot(at rootURL: URL) -> [AIControlNode] {
        subdirectories(of: rootURL)
            .map(classify)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func classify(_ url: URL) -> AIControlNode {
        if fileExists(url.appendingPathComponent(".project")) {
            return AIControlNode(url: url, kind: .project, projectFile: readProjectFile(at: url))
        }

        if fileExists(url.appendingPathComponent(".organize")) {
            let childURLs = subdirectories(of: url)
            let nestedWarning = childURLs.contains { fileExists($0.appendingPathComponent(".organize")) }
            let children = childURLs
                .map(classify)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return AIControlNode(url: url, kind: .organizer, children: children, nestedOrganizerWarning: nestedWarning)
        }

        return AIControlNode(url: url, kind: .untouched)
    }

    private func subdirectories(of url: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private func fileExists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func readProjectFile(at directoryURL: URL) -> ProjectFile {
        let fileURL = directoryURL.appendingPathComponent(".project")
        guard let data = try? Data(contentsOf: fileURL), let contents = String(data: data, encoding: .utf8) else {
            return ProjectFile()
        }
        return ProjectFileParser.parse(contents)
    }
}
