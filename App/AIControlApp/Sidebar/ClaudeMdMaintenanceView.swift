import SwiftUI
import AIControlCore

/// The MAINTENANCE section's CLAUDE.md row (PROJECT.md §6.3), driven by the
/// pure `ClaudeMdDriftDetector` plus global-config existence. Honesty rules
/// (see the Phase 6 UX notes): uncomputable states are dim placeholders, real
/// states carry no status color, and the Rebuild action appears only when the
/// file is genuinely out of date. Rebuild sends a stored prompt to the
/// project's own session — the app never edits CLAUDE.md itself.
struct ClaudeMdMaintenanceView: View {
    let file: ProjectFile
    let globalConfig: GlobalConfig
    let isRebuilding: Bool
    let onRebuild: () -> Void
    let onOpenSession: () -> Void

    /// The composed row state: global-config gating first, then drift.
    enum State: Equatable {
        case needsConfig
        case needsModules
        case notGenerated
        case upToDate(generatedOn: String)
        case outOfDate(changed: [String], removed: [String], generatedOn: String)
    }

    private var state: State {
        guard globalConfig.exists else { return .needsConfig }
        guard !globalConfig.modules.isEmpty else { return .needsModules }
        switch ClaudeMdDriftDetector.evaluate(
            generatedStamp: file.claudeMdGenerated,
            recordedModules: file.modules,
            moduleModifiedDates: globalConfig.moduleModifiedDates
        ) {
        case .notGenerated: return .notGenerated
        case .upToDate(let on): return .upToDate(generatedOn: on)
        case .outOfDate(let changed, let removed, let on):
            return .outOfDate(changed: changed, removed: removed, generatedOn: on)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow
            switch state {
            case .outOfDate(let changed, let removed, _):
                changedList(changed: changed, removed: removed)
                rebuildControls
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .needsConfig:
            SidebarKeyValue(key: "CLAUDE.md", value: "needs global config", placeholder: true)
        case .needsModules:
            SidebarKeyValue(key: "CLAUDE.md", value: "needs global modules", placeholder: true)
        case .notGenerated:
            SidebarKeyValue(key: "CLAUDE.md", value: "Not generated yet")
        case .upToDate:
            SidebarKeyValue(key: "CLAUDE.md", value: "Up to date")
        case .outOfDate:
            SidebarKeyValue(key: "CLAUDE.md", value: "Out of date")
        }
    }

    @ViewBuilder
    private func changedList(changed: [String], removed: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(removed.isEmpty ? "Changed since generated" : "Changed or removed since generated")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            MonospaceChips(items: changed + removed)
        }
    }

    @ViewBuilder
    private var rebuildControls: some View {
        if isRebuilding {
            // Honest async feedback: don't flip to "Up to date" — the row
            // self-heals when Claude rewrites `.project`. Just show progress.
            VStack(alignment: .leading, spacing: 2) {
                Text("Rebuilding… — Claude is regenerating CLAUDE.md in the terminal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open session", action: onOpenSession)
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        } else {
            Button(action: onRebuild) {
                Label("Rebuild", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
