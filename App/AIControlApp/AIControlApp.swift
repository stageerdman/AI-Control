import SwiftUI

@main
struct AIControlApp: App {
    // Shared stores live at app scope so both scenes — the dashboard and the
    // Global Config window — observe the same instances and reload in lockstep.
    @StateObject private var rootFolderStore: RootFolderStore
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var sessionStore: TerminalSessionStore
    @StateObject private var globalConfig: GlobalConfigStore
    @StateObject private var alerts: SessionAlerts

    @Environment(\.openWindow) private var openWindow

    init() {
        let root = RootFolderStore()
        let config = GlobalConfigStore()
        let sessions = TerminalSessionStore()
        sessions.globalConfig = config
        _rootFolderStore = StateObject(wrappedValue: root)
        _globalConfig = StateObject(wrappedValue: config)
        _sessionStore = StateObject(wrappedValue: sessions)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(rootFolderStore: root))
        _alerts = StateObject(wrappedValue: SessionAlerts())
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(
                rootFolderStore: rootFolderStore,
                viewModel: viewModel,
                sessionStore: sessionStore,
                globalConfig: globalConfig,
                alerts: alerts
            )
        }
        .commands {
            // A single, clearly-labelled top-level menu-bar menu — the one entry
            // point to the Global Config window, easy to spot at the top of the
            // screen. ⌘, opens it too.
            CommandMenu("Global Config") {
                Button("Open Global Config") { openWindow(id: GlobalConfigWindow.windowID) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Global Config", id: GlobalConfigWindow.windowID) {
            GlobalConfigWindow(
                globalConfig: globalConfig,
                rootFolderStore: rootFolderStore,
                sessionStore: sessionStore
            )
        }
    }
}
