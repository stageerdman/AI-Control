import Foundation

/// Turns the scanner's tree into the flat, ordered row list the dashboard
/// renders. Pure and stateless so it's fully unit-testable — the view layer
/// just calls `build` whenever nodes, expansion, or the search query change.
public enum DashboardListBuilder {
    public static func build(nodes: [AIControlNode], expandedIDs: Set<URL>, searchQuery: String) -> [DashboardRow] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return buildBrowsing(nodes: nodes, expandedIDs: expandedIDs)
        }
        return buildSearchResults(nodes: nodes, expandedIDs: expandedIDs, query: trimmedQuery)
    }

    /// No active search: top-level items ordered by recency; an expanded
    /// organizer's children insert directly beneath it, ordered by their own
    /// recency (expansion doesn't re-enter the global top-level sort).
    private static func buildBrowsing(nodes: [AIControlNode], expandedIDs: Set<URL>) -> [DashboardRow] {
        var rows: [DashboardRow] = []
        for node in sortedByRecency(nodes) {
            rows.append(DashboardRow(node: node, depth: 0))
            guard node.kind == .organizer, expandedIDs.contains(node.id) else { continue }
            rows.append(contentsOf: sortedByRecency(node.children).map { DashboardRow(node: $0, depth: 1) })
        }
        return rows
    }

    /// Active search: hierarchy flattens. A matching organizer keeps its
    /// children if expanded; a non-matching organizer contributes only its
    /// matching children as standalone anchors. Everything ends up depth 0,
    /// sorted by recency together.
    private static func buildSearchResults(nodes: [AIControlNode], expandedIDs: Set<URL>, query: String) -> [DashboardRow] {
        var matched: [AIControlNode] = []

        for node in nodes {
            switch node.kind {
            case .project, .untouched, .invalidNestedOrganizer:
                if matches(node, query: query) {
                    matched.append(node)
                }
            case .organizer:
                if matches(node, query: query) {
                    matched.append(node)
                    if expandedIDs.contains(node.id) {
                        matched.append(contentsOf: node.children)
                    }
                } else {
                    matched.append(contentsOf: node.children.filter { matches($0, query: query) })
                }
            }
        }

        return sortedByRecency(matched).map { DashboardRow(node: $0, depth: 0) }
    }

    private static func sortedByRecency(_ nodes: [AIControlNode]) -> [AIControlNode] {
        nodes.sorted { $0.lastActivityDate > $1.lastActivityDate }
    }

    private static func matches(_ node: AIControlNode, query: String) -> Bool {
        if node.name.range(of: query, options: .caseInsensitive) != nil {
            return true
        }
        guard node.kind == .project, let description = node.projectFile?.body, !description.isEmpty else {
            return false
        }
        return description.range(of: query, options: .caseInsensitive) != nil
    }
}
