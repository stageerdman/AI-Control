import SwiftUI
import AIControlCore

struct DashboardView: View {
    @StateObject private var rootFolderStore = RootFolderStore()
    @StateObject private var viewModel: DashboardViewModel
    @State private var isChoosingFolder = false
    @FocusState private var listIsFocused: Bool

    init() {
        let store = RootFolderStore()
        _rootFolderStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(rootFolderStore: store))
    }

    var body: some View {
        Group {
            if !viewModel.hasRootFolder {
                EmptyStateView(
                    systemImage: "folder.badge.plus",
                    title: "Point AI Control at a folder",
                    actionTitle: "Choose Folder",
                    action: { isChoosingFolder = true }
                )
            } else if viewModel.rows.isEmpty && viewModel.searchQuery.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "This folder is empty",
                    message: "Add a project folder to get started."
                )
            } else if viewModel.rows.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "No matches")
            } else {
                HSplitView {
                    rowList
                        .frame(minWidth: 280, idealWidth: 420)
                        .layoutPriority(1)
                    ProjectSidebarView(
                        node: viewModel.selectedNode,
                        gitStatus: viewModel.selectedGitStatus,
                        onBringUnderControl: revealInFinder,
                        onLetAIFix: revealInFinder
                    )
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 360)
        .searchable(text: $viewModel.searchQuery, placement: .toolbar, prompt: "Search")
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                viewModel.chooseRootFolder(url)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Choose Folder…") { isChoosingFolder = true }
            }
        }
    }

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.rows) { row in
                    DashboardRowView(
                        row: row,
                        isExpanded: isExpandedOrganizer(row),
                        isCursor: viewModel.cursorID == row.id,
                        isSelected: viewModel.selectedID == row.id
                    )
                    .onTapGesture {
                        viewModel.handleClick(on: row)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .top)
            .animation(.easeOut(duration: 0.2), value: viewModel.rows)
        }
        // Clicking empty space below/around the rows clears the selection.
        // Rows consume taps within their own bounds first, so this only
        // fires for genuinely empty area.
        .contentShape(Rectangle())
        .onTapGesture { viewModel.clearSelection() }
        .focusable()
        .focusEffectDisabled() // we draw our own per-row cursor ring instead of the system's whole-area ring
        .focused($listIsFocused)
        .onAppear { listIsFocused = true }
        .onKeyPress(.upArrow) { viewModel.moveCursorUp(); return .handled }
        .onKeyPress(.downArrow) { viewModel.moveCursorDown(); return .handled }
        .onKeyPress(.leftArrow) { viewModel.collapseCursor(); return .handled }
        .onKeyPress(.rightArrow) { viewModel.expandCursor(); return .handled }
        .onKeyPress(.return) { viewModel.activateCursor(); return .handled }
        .onKeyPress(.escape) { viewModel.clearSelection(); return .handled }
    }

    private func isExpandedOrganizer(_ row: DashboardRow) -> Bool {
        rootFolderStore.expandedIDs.contains(row.id)
    }

    /// Interim behavior for the AI-driven actions (adopt an untouched folder,
    /// fix an invalid nested organizer) until the AI window (Phase 4+) exists:
    /// reveal the folder in Finder, so the buttons do something real and
    /// non-misleading (their captions say so).
    private func revealInFinder(_ node: AIControlNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
}

#Preview {
    DashboardView()
}
