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
    @Published var selectedID: URL?

    private let rootFolderStore: RootFolderStore
    private let scanner: FolderScanner
    private var nodes: [AIControlNode] = []
    private var cancellables: Set<AnyCancellable> = []

    var rootURL: URL? { rootFolderStore.rootURL }
    var hasRootFolder: Bool { rootFolderStore.rootURL != nil }

    init(rootFolderStore: RootFolderStore, scanner: FolderScanner = FolderScanner()) {
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
