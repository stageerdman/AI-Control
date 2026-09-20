import Foundation

/// Parses a `.project` file's `---` frontmatter block plus body, per the
/// format proposed in `PROJECT.md` §4. The format is small and fixed, so a
/// minimal line-based parser is used instead of a full YAML dependency.
///
/// Malformed or missing frontmatter degrades gracefully: the whole file
/// contents become the body and every field stays at its default.
public enum ProjectFileParser {
    public static func parse(_ contents: String) -> ProjectFile {
        var result = ProjectFile()

        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespaces) == "---",
              let closingOffset = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              })
        else {
            result.body = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            return result
        }

        let frontmatterLines = lines[1..<closingOffset]
        let bodyLines = lines[(closingOffset + 1)...]
        result.body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        for rawLine in frontmatterLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let colonIndex = line.firstIndex(of: ":") else { continue }

            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if let hashRange = value.range(of: "#") {
                value = String(value[value.startIndex..<hashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            switch key {
            case "name": result.name = nilIfEmptyOrNull(value)
            case "github": result.github = nilIfEmptyOrNull(value)
            case "visibility": result.visibility = nilIfEmptyOrNull(value)
            case "adopted": result.adopted = nilIfEmptyOrNull(value)
            case "claude_md_generated": result.claudeMdGenerated = nilIfEmptyOrNull(value)
            case "modules": result.modules = parseList(value)
            case "secrets": result.secrets = parseList(value)
            default: break
            }
        }

        return result
    }

    private static func nilIfEmptyOrNull(_ value: String) -> String? {
        (value.isEmpty || value == "null" || value == "~") ? nil : value
    }

    private static func parseList(_ value: String) -> [String] {
        var value = value
        if value.hasPrefix("[") && value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
