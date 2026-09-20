import Foundation

/// Validates the New Project form inputs (PROJECT.md §9.2) before the app
/// creates the target folder and hands off to the AI. Pure logic so it's unit-
/// testable without UI: the app supplies the sibling names already present at
/// the chosen location and renders the returned problems.
public enum NewProjectValidator {
    public enum Problem: Equatable {
        case emptyName
        case invalidName
        case nameTaken
        case emptyDescription
    }

    /// The folder name derived from a display name: trimmed of surrounding
    /// whitespace. macOS allows spaces, so the name is otherwise preserved; only
    /// path separators and the special `.`/`..` entries are rejected (see
    /// `validate`). The AI later chooses the GitHub repo slug.
    public static func folderName(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// - Parameters:
    ///   - name: the raw display name from the form.
    ///   - description: the required INIT description.
    ///   - existingSiblingNames: names already present at the chosen location
    ///     (root or organizer), for the duplicate check (case-insensitive).
    public static func validate(
        name: String,
        description: String,
        existingSiblingNames: Set<String>
    ) -> [Problem] {
        var problems: [Problem] = []

        let folder = folderName(for: name)
        if folder.isEmpty {
            problems.append(.emptyName)
        } else if folder.contains("/") || folder == "." || folder == ".." || folder.hasPrefix(".") {
            problems.append(.invalidName)
        } else if existingSiblingNames.contains(where: { $0.caseInsensitiveCompare(folder) == .orderedSame }) {
            problems.append(.nameTaken)
        }

        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append(.emptyDescription)
        }

        return problems
    }

    /// Convenience: the inputs are ready to submit (no problems).
    public static func isValid(
        name: String,
        description: String,
        existingSiblingNames: Set<String>
    ) -> Bool {
        validate(name: name, description: description, existingSiblingNames: existingSiblingNames).isEmpty
    }
}
