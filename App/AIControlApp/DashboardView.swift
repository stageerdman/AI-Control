import SwiftUI
import AIControlCore

struct DashboardView: View {
    @StateObject private var rootFolderStore = RootFolderStore()
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var sessionStore = TerminalSessionStore()
    @StateObject private var alerts = SessionAlerts()
    @State private var isChoosingFolder = false
    @State private var openProject: OpenProject?
    @State private var lastTap: (id: URL, at: Date)?
    @FocusState private var listIsFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// The project currently shown full-window in the project view, paired with
    /// its live terminal session. Created on double-click (not during body), so
    /// the session store isn't mutated mid-render.
    private struct OpenProject: Identifiable {
        let node: AIControlNode
        let session: TerminalSession
        var id: URL { node.id }
    }

    init() {
        let store = RootFolderStore()
        _rootFolderStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(rootFolderStore: store))
    }

    var body: some View {
        Group {
            if let open = openProject {
                ProjectView(node: open.node, session: open.session) { openProject = nil }
            } else {
                dashboard
            }
        }
        // Session/alert state is synced here — on the always-present container,
        // not inside `dashboard` — so notifications and the Dock badge keep
        // updating while the user is inside a project view too.
        .onAppear {
            alerts.requestAuthorization()
            viewModel.setRunningURLs(sessionStore.runningURLs)
            viewModel.setAwaitingInputURLs(sessionStore.awaitingInputURLs)
            syncAlerts()
        }
        .onChange(of: sessionStore.runningURLs) { _, newValue in viewModel.setRunningURLs(newValue) }
        .onChange(of: sessionStore.awaitingInputURLs) { _, newValue in
            viewModel.setAwaitingInputURLs(newValue)
            syncAlerts()
        }
        .onChange(of: scenePhase) { _, _ in syncAlerts() }
        .onChange(of: openProject?.id) { _, _ in syncAlerts() }
        .onChange(of: alerts.pendingOpenURL) { _, url in
            guard let url else { return }
            openProjectByURL(url)
            alerts.pendingOpenURL = nil
        }
    }

    private var dashboard: some View {
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
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    DashboardRowView(
                        row: row,
                        isExpanded: isExpandedOrganizer(row),
                        isCursor: viewModel.cursorID == row.id,
                        isSelected: viewModel.selectedID == row.id,
                        isRunning: sessionStore.runningURLs.contains(row.id),
                        isAwaitingInput: sessionStore.awaitingInputURLs.contains(row.id)
                    )
                    .onTapGesture {
                        handleRowTap(row)
                    }
                    .overlay(
                        RowRightClick(
                            showsCloseSession: sessionStore.runningURLs.contains(row.id),
                            onSelect: { viewModel.select(row) },
                            onCloseSession: { closeSession(row) }
                        )
                    )

                    // Separate the pinned running sessions from the rest.
                    if viewModel.pinnedRunningCount > 0, index == viewModel.pinnedRunningCount - 1 {
                        Divider().padding(.vertical, 2)
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

    /// Handles a single click, detecting a double-click manually by timing.
    /// This keeps single-click **instant** — a SwiftUI `.onTapGesture(count: 2)`
    /// would delay every single click while it waited to disambiguate.
    private func handleRowTap(_ row: DashboardRow) {
        let now = Date()
        if let last = lastTap, last.id == row.id, now.timeIntervalSince(last.at) < 0.4 {
            lastTap = nil
            openProjectView(row)
        } else {
            lastTap = (row.id, now)
            viewModel.handleClick(on: row)
        }
    }

    /// Double-clicking a project opens its terminal session in the project
    /// view (PROJECT.md §8.1/§8.3). Only projects have a session; other row
    /// kinds are inert on double-click for now.
    private func openProjectView(_ row: DashboardRow) {
        guard row.node.kind == .project else { return }
        viewModel.handleClick(on: row) // keep the selection in sync
        openProject = OpenProject(node: row.node, session: sessionStore.session(for: row.node.url))
    }

    /// Opens a project by URL (used when a notification is clicked). No-op if the
    /// URL no longer resolves to a project.
    private func openProjectByURL(_ url: URL) {
        guard let node = viewModel.node(for: url), node.kind == .project else { return }
        viewModel.selectedID = url
        openProject = OpenProject(node: node, session: sessionStore.session(for: url))
    }

    /// Pushes the current awaiting/foreground/active state into `SessionAlerts`,
    /// which owns the notification + Dock-badge behavior.
    private func syncAlerts() {
        alerts.update(
            awaiting: sessionStore.awaitingInputURLs,
            foreground: openProject?.id,
            appActive: scenePhase == .active,
            name: { viewModel.node(for: $0)?.name ?? "Project" }
        )
    }

    /// Closes a running session (right-click action). Opening is via
    /// double-click, so there's no "Open Session" menu item.
    private func closeSession(_ row: DashboardRow) {
        sessionStore.stopSession(for: row.node.url)
        if openProject?.id == row.id { openProject = nil }
    }
}

#Preview {
    DashboardView()
}
