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

    /// Git state for `selectedNode`. `nil` while a read is in flight (or when
    /// nothing is selected); the sidebar shows a loading state then. A folder
    /// that isn't a repo resolves to `.notARepository`, not `nil`.
    @Published private(set) var selectedGitStatus: GitStatus?

    private let rootFolderStore: RootFolderStore
    private let scanner: FolderScanner
    private let gitStatusReader: GitStatusReader
    private var nodes: [AIControlNode] = []
    private var cancellables: Set<AnyCancellable> = []
    /// Guards against a slow git read for a since-changed selection landing on
    /// the wrong node.
    private var gitReadToken = UUID()

    var rootURL: URL? { rootFolderStore.rootURL }
    var hasRootFolder: Bool { rootFolderStore.rootURL != nil }

    init(
        rootFolderStore: RootFolderStore,
        scanner: FolderScanner = FolderScanner(),
        gitStatusReader: GitStatusReader = GitStatusReader()
    ) {
        self.rootFolderStore = rootFolderStore
        self.scanner = scanner
        self.gitStatusReader = gitStatusReader

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

    /// Recomputes `selectedNode` from `selectedID` and kicks off a fresh git
    /// read for it. Called whenever the selection changes or the tree rescans.
    private func refreshSelection() {
        let node = selectedID.flatMap { findNode(withID: $0) }
        selectedNode = node
        selectedGitStatus = nil

        gitReadToken = UUID()
        guard let node else { return }
        let token = gitReadToken
        let url = node.url
        let reader = gitStatusReader
        Task.detached(priority: .userInitiated) {
            let status = reader.status(for: url)
            await MainActor.run {
                // Ignore results for a selection the user has since moved off.
                guard self.gitReadToken == token else { return }
                self.selectedGitStatus = status
            }
        }
    }

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
        rows = DashboardListBuilder.build(
            nodes: nodes,
            expandedIDs: rootFolderStore.expandedIDs,
            searchQuery: searchQuery
        )
    }
}
