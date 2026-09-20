import Foundation

/// One flattened row ready for the dashboard list to render: a node plus how
/// deeply indented it is (0 = top-level, 1 = shown under an expanded
/// organizer). Built by `DashboardListBuilder`.
public struct DashboardRow: Identifiable, Equatable {
    public let node: AIControlNode
    public let depth: Int

    public var id: URL { node.id }

    public init(node: AIControlNode, depth: Int) {
        self.node = node
        self.depth = depth
    }
}
