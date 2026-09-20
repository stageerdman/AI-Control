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
    /// level deeper to list their projects. Nested organizers aren't
    /// allowed (`PROJECT.md` §3.2): an `.organize` folder found inside
    /// another organizer is never treated as a working organizer — it's
    /// classified `.invalidNestedOrganizer` instead, with no children
    /// scanned, while the parent gets `nestedOrganizerWarning` so it can be
    /// told to fix it.
    public func scanRoot(at rootURL: URL) -> [AIControlNode] {
        subdirectories(of: rootURL)
            .map { classify($0, isChildOfOrganizer: false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func classify(_ url: URL, isChildOfOrganizer: Bool) -> AIControlNode {
        let ownModificationDate = modificationDate(of: url)

        if fileExists(url.appendingPathComponent(".project")) {
            return AIControlNode(
                url: url,
                kind: .project,
                projectFile: readProjectFile(at: url),
                lastActivityDate: ownModificationDate
            )
        }

        let hasOrganizeMarker = fileExists(url.appendingPathComponent(".organize"))

        if hasOrganizeMarker && isChildOfOrganizer {
            return AIControlNode(url: url, kind: .invalidNestedOrganizer, lastActivityDate: ownModificationDate)
        }

        if hasOrganizeMarker {
            let childURLs = subdirectories(of: url)
            let nestedWarning = childURLs.contains { fileExists($0.appendingPathComponent(".organize")) }
            let children = childURLs
                .map { classify($0, isChildOfOrganizer: true) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let latestChildDate = children.map(\.lastActivityDate).max()
            return AIControlNode(
                url: url,
                kind: .organizer,
                children: children,
                nestedOrganizerWarning: nestedWarning,
                lastActivityDate: latestChildDate ?? ownModificationDate
            )
        }

        return AIControlNode(url: url, kind: .untouched, lastActivityDate: ownModificationDate)
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

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func readProjectFile(at directoryURL: URL) -> ProjectFile {
        let fileURL = directoryURL.appendingPathComponent(".project")
        guard let data = try? Data(contentsOf: fileURL), let contents = String(data: data, encoding: .utf8) else {
            return ProjectFile()
        }
        return ProjectFileParser.parse(contents)
    }
}
