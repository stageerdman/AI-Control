import SwiftUI
import AIControlCore

struct DashboardView: View {
    // Owned by the app scene (so the Global Config window shares them); observed
    // here.
    @ObservedObject var rootFolderStore: RootFolderStore
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var sessionStore: TerminalSessionStore
    @ObservedObject var globalConfig: GlobalConfigStore
    @ObservedObject var alerts: SessionAlerts
    @State private var isChoosingFolder = false
    @State private var isCreatingProject = false
    @State private var openProject: OpenProject?
    @State private var lastTap: (id: URL, at: Date)?
    @State private var scrollTarget: URL?
    @FocusState private var listIsFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    /// The project currently shown full-window in the project view, paired with
    /// its live terminal session. Created on double-click (not during body), so
    /// the session store isn't mutated mid-render.
    private struct OpenProject: Identifiable {
        let node: AIControlNode
        let session: TerminalSession
        var id: URL { node.id }
    }


    var body: some View {
        VStack(spacing: 0) {
            if !alerts.attentionURLs.isEmpty {
                AttentionBannerView(
                    count: alerts.attentionURLs.count,
                    primaryName: alerts.names[alerts.attentionURLs[0]] ?? "A project",
                    onPrimary: handleBannerPrimary,
                    onDismiss: alerts.dismissAll
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if let open = openProject {
                    ProjectView(node: open.node, session: open.session) {
                        openProject = nil
                        viewModel.rescan() // pick up a just-created/changed .project
                    }
                } else {
                    dashboard
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: alerts.attentionURLs)
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
        .onChange(of: scenePhase) { _, phase in
            syncAlerts()
            // Returning to the app re-reads the global config and rescans, so a
            // module edit or a Rebuild's `.project` rewrite recomputes drift.
            if phase == .active {
                globalConfig.reload()
                viewModel.rescan()
            }
        }
        // When a Rebuild finishes (URL leaves the rebuilding set), re-read so the
        // drift row self-heals from Claude's `.project` rewrite.
        .onChange(of: sessionStore.rebuildingURLs) { _, _ in
            globalConfig.reload()
            viewModel.rescan()
        }
        // An AI-window turn finished (e.g. an adopt/fix wrote markers) → rescan so
        // the row reclassifies without a relaunch.
        .onChange(of: sessionStore.aiActivityTick) { _, _ in viewModel.rescan() }
        .onChange(of: openProject?.id) { _, _ in syncAlerts() }
        .onChange(of: alerts.pendingOpenURL) { _, url in
            guard let url else { return }
            openProjectByURL(url)
            alerts.pendingOpenURL = nil
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            if viewModel.hasRootFolder && !globalConfig.isSetUp {
                GlobalConfigBanner(onSetUp: { openWindow(id: GlobalConfigWindow.windowID) })
            }
            dashboardBody
        }
    }

    private var dashboardBody: some View {
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
                    message: "Create your first project, or add folders to this location outside the app.",
                    actionTitle: "New Project",
                    action: { isCreatingProject = true }
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
                        globalConfig: globalConfig.config,
                        isRebuilding: viewModel.selectedNode.map { sessionStore.isRebuilding($0.url) } ?? false,
                        onBringUnderControl: adoptFolder,
                        onLetAIFix: fixNesting,
                        onRebuild: rebuild,
                        onOpenSession: openSessionForNode
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
            ToolbarItem(placement: .primaryAction) {
                Button { isCreatingProject = true } label: {
                    Label("New Project", systemImage: "plus")
                }
                .disabled(!viewModel.hasRootFolder)
                .help(viewModel.hasRootFolder ? "New Project" : "Connect a root folder first.")
            }
            ToolbarItem(placement: .automatic) {
                Button("Choose Folder…") { isChoosingFolder = true }
            }
        }
        .sheet(isPresented: $isCreatingProject) {
            if let root = viewModel.rootURL {
                NewProjectSheet(
                    rootURL: root,
                    organizers: viewModel.organizers,
                    globalConfig: globalConfig.config,
                    onSetUpConfig: { openWindow(id: GlobalConfigWindow.windowID) },
                    onCreate: { dir, name, visibility, description in
                        isCreatingProject = false
                        createProject(at: dir, name: name, visibility: visibility, description: description)
                    },
                    onCancel: { isCreatingProject = false }
                )
            }
        }
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
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
                            isRunning: sessionStore.runningURLs.contains(row.id),
                            isStopping: sessionStore.isStopping(row.id),
                            onSelect: { viewModel.select(row) },
                            onAskAI: { askAI(row.node) },
                            onStop: { stopRoutine(row) },
                            onForceClose: { closeSession(row) }
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
        .onChange(of: scrollTarget) { _, target in
            guard let target else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .top) }
            scrollTarget = nil
        }
        }
    }

    private func isExpandedOrganizer(_ row: DashboardRow) -> Bool {
        rootFolderStore.expandedIDs.contains(row.id)
    }

    /// Bring an untouched folder under AI Control (§9.3): send the report-first
    /// adopt prompt + path to the AI window and raise it. The AI reports a verdict
    /// and applies changes on the user's "yes" — the app touches nothing.
    private func adoptFolder(_ node: AIControlNode) {
        guard let root = viewModel.rootURL else { return }
        sessionStore.adopt(folderURL: node.url, rootURL: root)
        openWindow(id: AIWindow.windowID)
    }

    /// Fix an invalid nested organizer via the AI window (adopt prompt + fix
    /// appendix).
    private func fixNesting(_ node: AIControlNode) {
        guard let root = viewModel.rootURL else { return }
        sessionStore.fixNesting(folderURL: node.url, rootURL: root)
        openWindow(id: AIWindow.windowID)
    }

    /// Right-click "Ask AI…": hand the folder to the AI window. Untouched/invalid
    /// folders get the directed adopt/fix prompt; projects/organizers get an
    /// editable pre-filled reference line (§8.4).
    private func askAI(_ node: AIControlNode) {
        guard let root = viewModel.rootURL else { return }
        switch node.kind {
        case .untouched: sessionStore.adopt(folderURL: node.url, rootURL: root)
        case .invalidNestedOrganizer: sessionStore.fixNesting(folderURL: node.url, rootURL: root)
        default: sessionStore.askAI(about: node.url, rootURL: root)
        }
        openWindow(id: AIWindow.windowID)
    }

    /// New Project (§9.2): create the empty target dir + open its AI session, then
    /// show it full-window so the user watches the AI build it. A synthetic
    /// `.project` node stands in until the scan picks up the real `.project`
    /// marker; on return we rescan so the row appears.
    private func createProject(at dir: URL, name: String, visibility: String, description: String) {
        guard let session = sessionStore.startNewProject(at: dir, name: name, visibility: visibility, initDescription: description) else {
            // Directory already existed (lost the race) — reopen the form so the
            // name can be changed; never send the prompt into a non-empty folder.
            isCreatingProject = true
            return
        }
        let node = AIControlNode(url: dir, kind: .project, lastActivityDate: Date())
        openProject = OpenProject(node: node, session: session)
    }

    /// Rebuild CLAUDE.md: sends the stored prompt into the project's own session
    /// (starting one if needed). The AI regenerates the file; the app never
    /// touches it (principle 2).
    private func rebuild(_ node: AIControlNode) {
        sessionStore.rebuildClaudeMd(for: node.url)
    }

    /// Opens the project's terminal session full-window (to watch a rebuild).
    private func openSessionForNode(_ node: AIControlNode) {
        guard node.kind == .project else { return }
        viewModel.selectedID = node.url
        openProject = OpenProject(node: node, session: sessionStore.session(for: node.url))
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

    /// The red banner's primary action. One project waiting → open it. Several →
    /// leave any project view and land on the dashboard at the top awaiting row,
    /// where every awaiting row glows so the user picks the specific one.
    private func handleBannerPrimary() {
        let urls = alerts.attentionURLs
        if urls.count == 1, let url = urls.first {
            openProjectByURL(url)
        } else {
            openProject = nil
            if let topAwaiting = viewModel.rows.first(where: { sessionStore.awaitingInputURLs.contains($0.id) }) {
                viewModel.selectedID = topAwaiting.id
                viewModel.cursorID = topAwaiting.id
                scrollTarget = topAwaiting.id
            }
        }
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

    /// Graceful Stop (right-click): asks Claude to wrap up (save, commit, push)
    /// and then closes the session. The session keeps running visibly while it
    /// wraps up, so we don't leave the project view here.
    private func stopRoutine(_ row: DashboardRow) {
        sessionStore.runStopRoutine(for: row.node.url)
    }

    /// Force Close (right-click): kills a running session immediately. Opening is
    /// via double-click, so there's no "Open Session" menu item.
    private func closeSession(_ row: DashboardRow) {
        sessionStore.stopSession(for: row.node.url)
        if openProject?.id == row.id { openProject = nil }
    }
}

#Preview {
    let root = RootFolderStore()
    return DashboardView(
        rootFolderStore: root,
        viewModel: DashboardViewModel(rootFolderStore: root),
        sessionStore: TerminalSessionStore(),
        globalConfig: GlobalConfigStore(),
        alerts: SessionAlerts()
    )
}
