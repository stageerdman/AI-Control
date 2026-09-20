import SwiftUI
import AIControlCore

/// The dedicated Global Config control window (opened via Settings ⌘,, the
/// Window menu, or the dashboard gear). A `NavigationSplitView` over the whole
/// `~/.ai-control/` repo (PROJECT.md §6, §8.5/§8.6 folded into one window).
///
/// MVP scope: honest, live *visibility* of every part of the config plus
/// Reveal-in-Finder / Open-in-editor on each — the user's "just let me open the
/// folder and edit inside there," promoted to one click. In-app text editing is
/// deferred. Reuses the sidebar component vocabulary so it looks like the app.
struct GlobalConfigWindow: View {
    static let windowID = "global-config"

    @ObservedObject var globalConfig: GlobalConfigStore
    @ObservedObject var rootFolderStore: RootFolderStore
    @ObservedObject var sessionStore: TerminalSessionStore

    @State private var selection: Section? = .overview
    @State private var justCreated = false
    @State private var isChoosingRoot = false
    @State private var draftSession: TerminalSession?
    @Environment(\.controlActiveState) private var controlActiveState

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", modules = "Modules", wiki = "Wiki"
        case prompts = "Prompts", secrets = "Secrets", general = "General"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .overview: return "shippingbox"
            case .modules: return "doc.text"
            case .wiki: return "book"
            case .prompts: return "text.bubble"
            case .secrets: return "key"
            case .general: return "folder"
            }
        }
    }

    private var config: GlobalConfig { globalConfig.config }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(Optional(section))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        }
        .frame(minWidth: 640, idealWidth: 780, minHeight: 420)
        .onAppear { globalConfig.reload() }
        .onChange(of: controlActiveState) { _, state in
            if state != .inactive { globalConfig.reload() }
        }
        .fileImporter(isPresented: $isChoosingRoot, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { rootFolderStore.rootURL = url }
        }
        .sheet(item: $draftSession) { session in
            DraftModulesSheet(session: session) {
                draftSession = nil
                globalConfig.reload()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview: overview
        case .modules: modules
        case .wiki: wiki
        case .prompts: prompts
        case .secrets: secrets
        case .general: general
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeader(systemImage: "shippingbox", isAccent: true, name: "Global config", caption: config.root.path)

            Text("This is the shared brain every project inherits. Coding principles, workflow rules, knowledge pages, routine prompts and secrets live in ~/.ai-control/ and are reused across all your projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SidebarSection(title: "Status") {
                SidebarKeyValue(key: "Global config", value: statusValue, placeholder: !config.exists)
                if !config.exists {
                    Button("Create global config") {
                        try? globalConfig.createSkeleton()
                        justCreated = true
                    }
                    .buttonStyle(.borderedProminent)
                } else if justCreated {
                    Text("Created ~/.ai-control/ (skeleton). Modules aren't authored yet — draft them with the AI below.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if config.exists {
                if config.modules.isEmpty {
                    SidebarSection(title: "Modules") {
                        Text("No modules authored yet. Let the AI interview you and draft UX / WORKFLOW / STRUCTURE / CODING from your answers — you edit the result.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            draftSession = sessionStore.authorModules(at: config.root)
                        } label: {
                            Label("Draft modules with AI", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SidebarSection(title: "Contents") {
                    SidebarKeyValue(key: "Modules", value: "\(config.modules.count)")
                    SidebarKeyValue(key: "Wiki pages", value: "\(config.wikiPages.count)")
                    SidebarKeyValue(key: "Prompts", value: "\(RoutinePromptKind.allCases.count) (\(editedPromptCount) edited)")
                    SidebarKeyValue(key: "Secrets", value: "\(config.secretNames.count)")
                }
                ConfigFolderActions(folderURL: config.root, fileURL: globalConfig.readmeURL, openLabel: "Open README")
            }
        }
    }

    private var statusValue: String {
        guard config.exists else { return "not set up" }
        return config.modules.isEmpty ? "Skeleton created · no modules authored yet" : "Ready · \(config.modules.count) modules"
    }

    private var editedPromptCount: Int {
        RoutinePromptKind.allCases.filter { globalConfig.isPromptEdited($0) }.count
    }

    // MARK: - Modules

    @ViewBuilder
    private var modules: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeader(systemImage: "doc.text", isAccent: false, name: "Modules", caption: "Merged into each project's CLAUDE.md")
            Text("Modules are authored by the AI (or by you), never by the app.")
                .font(.caption).foregroundStyle(.tertiary)

            if !config.exists {
                notSetUpNote
            } else if config.modules.isEmpty {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: "No modules authored yet",
                    message: "Let the AI draft them from a short interview, or write them by hand in the folder."
                )
                Button { draftSession = sessionStore.authorModules(at: config.root) } label: {
                    Label("Draft modules with AI", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            } else {
                SidebarSection(title: "Files") {
                    ForEach(config.modules, id: \.name) { module in
                        SidebarKeyValue(key: module.name, value: "changed \(SidebarFormat.relativeString(module.modifiedAt))")
                    }
                }
            }
            if config.exists {
                ConfigFolderActions(folderURL: globalConfig.modulesURL)
            }
        }
    }

    // MARK: - Wiki

    @ViewBuilder
    private var wiki: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeader(systemImage: "book", isAccent: false, name: "Wiki", caption: "Knowledge pages the AI reads and writes")
            Text("Each page starts with a one-line usage description so search can find it.")
                .font(.caption).foregroundStyle(.tertiary)

            if !config.exists {
                notSetUpNote
            } else if config.wikiPages.isEmpty {
                EmptyStateView(systemImage: "book", title: "No wiki pages yet", message: "Pages are created by you and the AI as lessons are learned.")
            } else {
                SidebarSection(title: "Pages") {
                    ForEach(config.wikiPages, id: \.name) { page in
                        SidebarKeyValue(key: page.name, value: page.usageDescription ?? "—", placeholder: page.usageDescription == nil)
                    }
                }
            }
            if config.exists {
                ConfigFolderActions(folderURL: globalConfig.wikiURL)
            }
        }
    }

    // MARK: - Prompts

    @ViewBuilder
    private var prompts: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeader(systemImage: "text.bubble", isAccent: false, name: "Prompts", caption: "What the app's buttons send to Claude")
            Text("Edit a prompt to change what that routine does. Missing files fall back to a built-in default.")
                .font(.caption).foregroundStyle(.tertiary)

            if !config.exists {
                notSetUpNote
            } else {
                SidebarSection(title: "Routines") {
                    ForEach(RoutinePromptKind.allCases, id: \.self) { kind in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(kind.title).font(.caption).foregroundStyle(.secondary)
                            Text(globalConfig.isPromptEdited(kind) ? "Edited" : "Default")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer(minLength: 8)
                            Button("Open in editor") { NSWorkspace.shared.open(globalConfig.promptFileURL(for: kind)) }
                                .controlSize(.small)
                        }
                    }
                }
                ConfigFolderActions(folderURL: globalConfig.promptsURL)
            }
        }
    }

    // MARK: - Secrets

    @ViewBuilder
    private var secrets: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeader(systemImage: "key", isAccent: false, name: "Secrets", caption: "Shared with projects; values live only in .env")
            if !config.exists {
                notSetUpNote
            } else if config.secretNames.isEmpty {
                EmptyStateView(systemImage: "key", title: "No secrets yet", message: "Add keys to .env as KEY=value, one per line.")
            } else {
                SidebarSection(title: "Keys") {
                    MonospaceChips(items: config.secretNames)
                }
            }
            if config.exists {
                Text("In-app add/edit coming later.").font(.caption2).foregroundStyle(.tertiary)
                ConfigFolderActions(fileURL: globalConfig.envURL)
            }
        }
    }

    // MARK: - General

    @ViewBuilder
    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            SidebarHeader(systemImage: "folder", isAccent: false, name: "General", caption: "Root folder and config location")
            SidebarSection(title: "Root folder") {
                SidebarKeyValue(key: "Root", value: rootFolderStore.rootURL?.path ?? "not connected", placeholder: rootFolderStore.rootURL == nil)
                Button("Change…") { isChoosingRoot = true }.controlSize(.small)
            }
            SidebarSection(title: "Config repo") {
                SidebarKeyValue(key: "Location", value: config.root.path)
                if config.exists { ConfigFolderActions(folderURL: config.root) }
            }
        }
    }

    private var notSetUpNote: some View {
        Text("Global config isn't set up yet. Create it from the Overview tab.")
            .font(.caption).foregroundStyle(.tertiary)
    }
}

/// The one new reusable piece: a right-aligned pair of small actions to reveal a
/// path in Finder and/or open a file in the default editor. Kept as low-chrome
/// as `SidebarKeyValue`.
struct ConfigFolderActions: View {
    var folderURL: URL? = nil
    var fileURL: URL? = nil
    var openLabel: String = "Open in editor"

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            if let target = fileURL ?? folderURL {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([target]) }
                    .controlSize(.small)
            }
            if let file = fileURL {
                Button(openLabel) { NSWorkspace.shared.open(file) }
                    .controlSize(.small)
            } else if let folder = folderURL {
                Button("Open Folder") { NSWorkspace.shared.open(folder) }
                    .controlSize(.small)
            }
        }
    }
}

/// A sheet hosting the root-scoped Claude session that runs the module-authoring
/// interview (Option C). The AI asks questions and writes the module files; on
/// Done the window reloads so the new modules appear and status self-heals.
private struct DraftModulesSheet: View {
    @ObservedObject var session: TerminalSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Draft modules with AI", systemImage: "sparkles").font(.headline)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            TerminalContainerView(session: session)
                .frame(minWidth: 720, minHeight: 460)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
