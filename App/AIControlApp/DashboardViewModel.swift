import Foundation
import Combine
import AIControlCore

/// Owns the scan, the row-building, and the interaction state described in
/// the Phase 2 plan: `cursorID` (keyboard/click focus, moves through every
/// visible row) is kept separate from `selectedID` (the persistent,
/// accent-highlighted selection). Every row kind selects uniformly on
/// click/Enter — selection is what a future right-click/AI action targets —
/// organizers additionally toggle expansion, since clicking one also opens
/// it.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var rows: [DashboardRow] = []
    @Published var searchQuery: String = "" {
        didSet { rebuildRows() }
    }
    @Published var cursorID: URL?
    @Published var selectedID: URL? {
        didSet { if selectedID != oldValue { refreshSelection() } }
    }

    /// The node the sidebar is describing, resolved from `selectedID` across
    /// top-level nodes and organizer children.
    @Published private(set) var selectedNode: AIControlNode?

    /// Number of pinned running-session rows at the top of `rows`, so the view
    /// can draw a divider between them and the rest of the dashboard.
    @Published private(set) var pinnedRunningCount = 0

    /// Projects with a live terminal session, pinned on top of the list
    /// (PROJECT.md §8.1). Fed from the `TerminalSessionStore`.
    private var runningURLs: Set<URL> = []

    /// Running projects whose session is awaiting the user's reply. Sorted to the
    /// top of the pinned group so the top of the list is the actionable queue
    /// (Phase 5 UX pass). Fed from the `TerminalSessionStore`.
    private var awaitingInputURLs: Set<URL> = []

    private let rootFolderStore: RootFolderStore
    private let scanner: FolderScanner
    private var nodes: [AIControlNode] = []
    private var cancellables: Set<AnyCancellable> = []

    var rootURL: URL? { rootFolderStore.rootURL }
    var hasRootFolder: Bool { rootFolderStore.rootURL != nil }

    init(
        rootFolderStore: RootFolderStore,
        scanner: FolderScanner = FolderScanner()
    ) {
        self.rootFolderStore = rootFolderStore
        self.scanner = scanner

        rootFolderStore.$rootURL
            .sink { [weak self] _ in self?.rescan() }
            .store(in: &cancellables)
        rootFolderStore.$expandedIDs
            .sink { [weak self] _ in self?.rebuildRows() }
            .store(in: &cancellables)

        rescan()
    }

    func chooseRootFolder(_ url: URL) {
        rootFolderStore.rootURL = url
    }

    func rescan() {
        guard let rootURL = rootFolderStore.rootURL else {
            nodes = []
            rebuildRows()
            return
        }
        nodes = scanner.scanRoot(at: rootURL)
        rebuildRows()
        refreshSelection()
    }

    /// Every row selects on click, uniformly — selection is what a future
    /// right-click/AI action will target, regardless of kind. Organizers
    /// additionally toggle expansion, since clicking one is also how you
    /// open it.
    func handleClick(on row: DashboardRow) {
        cursorID = row.id
        selectedID = row.id
        if row.node.kind == .organizer {
            toggleExpanded(row.id)
        }
    }

    func moveCursorUp() { moveCursor(by: -1) }
    func moveCursorDown() { moveCursor(by: 1) }

    func expandCursor() {
        guard let row = currentCursorRow(), row.node.kind == .organizer else { return }
        rootFolderStore.expandedIDs.insert(row.id)
    }

    func collapseCursor() {
        guard let row = currentCursorRow(), row.node.kind == .organizer else { return }
        rootFolderStore.expandedIDs.remove(row.id)
    }

    /// Enter: activates the row at the cursor — same rule as a click. Lets
    /// pure-keyboard navigation reach the same end state as clicking.
    func activateCursor() {
        guard let row = currentCursorRow() else { return }
        selectedID = row.id
        if row.node.kind == .organizer {
            toggleExpanded(row.id)
        }
    }

    func clearSelection() {
        cursorID = nil
        selectedID = nil
    }

    /// Selects a row without any side effects (no organizer expand toggle).
    /// Used by right-click so the row highlights to show what's being acted on.
    func select(_ row: DashboardRow) {
        cursorID = row.id
        selectedID = row.id
    }

    /// Recomputes `selectedNode` from `selectedID`. Cheap (an in-memory lookup)
    /// — no git or other I/O, so clicking between rows is instant. GitHub info
    /// in the sidebar comes from `.project`, not a per-click `git` call.
    private func refreshSelection() {
        selectedNode = selectedID.flatMap { findNode(withID: $0) }
    }

    /// Updates which projects have a running session (pinned on top).
    func setRunningURLs(_ urls: Set<URL>) {
        guard urls != runningURLs else { return }
        runningURLs = urls
        rebuildRows()
    }

    /// Updates which running projects are awaiting the user's reply (sorted to
    /// the top of the pinned group).
    func setAwaitingInputURLs(_ urls: Set<URL>) {
        guard urls != awaitingInputURLs else { return }
        awaitingInputURLs = urls
        rebuildRows()
    }

    /// Resolves a project/organizer node by its URL, for callers that only have
    /// a URL (e.g. opening a project from a notification click).
    func node(for url: URL) -> AIControlNode? { findNode(withID: url) }

    /// Finds a node by URL across top-level nodes and organizer children
    /// (the tree is only ever two levels deep — no nested organizers).
    private func findNode(withID id: URL) -> AIControlNode? {
        for node in nodes {
            if node.id == id { return node }
            if let child = node.children.first(where: { $0.id == id }) { return child }
        }
        return nil
    }

    private func toggleExpanded(_ id: URL) {
        if rootFolderStore.expandedIDs.contains(id) {
            rootFolderStore.expandedIDs.remove(id)
        } else {
            rootFolderStore.expandedIDs.insert(id)
        }
    }

    private func currentCursorRow() -> DashboardRow? {
        guard let cursorID else { return nil }
        return rows.first { $0.id == cursorID }
    }

    private func moveCursor(by offset: Int) {
        guard !rows.isEmpty else { return }
        guard let currentCursorID = cursorID,
              let currentIndex = rows.firstIndex(where: { $0.id == currentCursorID })
        else {
            cursorID = offset > 0 ? rows.first?.id : rows.last?.id
            return
        }
        let newIndex = currentIndex + offset
        guard rows.indices.contains(newIndex) else { return }
        cursorID = rows[newIndex].id
    }

    private func rebuildRows() {
        let base = DashboardListBuilder.build(
            nodes: nodes,
            expandedIDs: rootFolderStore.expandedIDs,
            searchQuery: searchQuery
        )
        rows = pinningRunningSessions(base)
    }

    /// Pins projects with a live session to the top of the list at depth 0
    /// (PROJECT.md §8.1: "running sessions are pinned on top"), most-recent
    /// first, and removes them from their normal position so they aren't shown
    /// twice. Skipped while searching, so search results aren't reordered.
    private func pinningRunningSessions(_ base: [DashboardRow]) -> [DashboardRow] {
        pinnedRunningCount = 0
        guard !runningURLs.isEmpty, searchQuery.isEmpty else { return base }

        // Awaiting-input sessions first (the actionable queue), then working
        // ones; within each group, most-recent first. Single group, no extra
        // divider between the two — the ordering alone conveys it (UX pass).
        let pinnedNodes = runningURLs
            .compactMap { findNode(withID: $0) }
            .filter { $0.kind == .project }
            .sorted { lhs, rhs in
                let lAwaiting = awaitingInputURLs.contains(lhs.id)
                let rAwaiting = awaitingInputURLs.contains(rhs.id)
                if lAwaiting != rAwaiting { return lAwaiting }
                return lhs.lastActivityDate > rhs.lastActivityDate
            }

        guard !pinnedNodes.isEmpty else { return base }

        let pinnedIDs = Set(pinnedNodes.map(\.id))
        let pinnedRows = pinnedNodes.map { DashboardRow(node: $0, depth: 0) }
        let rest = base.filter { !pinnedIDs.contains($0.id) }
        pinnedRunningCount = pinnedRows.count
        return pinnedRows + rest
    }
}
