import SwiftUI
import AIControlCore

/// The right-hand detail pane. Read-only for Phase 3 (the single exception is
/// the untouched folder's "Bring under AI Control" action, which routes to an
/// interim behavior until the AI window exists). Dispatches on node kind;
/// nothing selected shows the empty state. Anything that depends on the
/// not-yet-built global config or session logs is shown as an honest
/// placeholder, never a faked status.
struct ProjectSidebarView: View {
    let node: AIControlNode?
    /// Interim actions for the two AI-driven flows until the AI window
    /// (Phase 4+) exists: adopting an untouched folder (Phase 9.3) and fixing
    /// an invalid nested organizer. Both hand a folder + a predefined prompt
    /// to the AI later; for now they reveal the folder in Finder.
    let onBringUnderControl: (AIControlNode) -> Void
    let onLetAIFix: (AIControlNode) -> Void

    var body: some View {
        Group {
            switch node?.kind {
            case .none:
                SidebarEmptyState()
            case .project:
                ProjectDetail(node: node!)
            case .organizer:
                OrganizerDetail(node: node!)
            case .untouched:
                UntouchedDetail(node: node!, onBringUnderControl: onBringUnderControl)
            case .invalidNestedOrganizer:
                InvalidNestedDetail(node: node!, onLetAIFix: onLetAIFix)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }
}

/// Vertically-scrolling column beneath a pinned header, shared by the detail
/// variants that have real sections.
private struct SidebarScaffold<Content: View>: View {
    let header: SidebarHeader
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding([.horizontal, .top], 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }
}

// MARK: - Project

private struct ProjectDetail: View {
    let node: AIControlNode

    private var file: ProjectFile { node.projectFile ?? ProjectFile() }

    var body: some View {
        SidebarScaffold(
            header: SidebarHeader(
                systemImage: "folder.fill",
                isAccent: true,
                name: node.name,
                caption: "Under AI Control"
            )
        ) {
            descriptionSection
            GitHubSection(githubURL: file.github, visibility: file.visibility)
            secretsSection
            maintenanceSection
            activitySection
            detailsSection
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if file.body.isEmpty {
            Text("No description yet.")
                .font(.body)
                .italic()
                .foregroundStyle(.tertiary)
        } else {
            Text(file.body)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var secretsSection: some View {
        SidebarSection(title: "Secrets") {
            if file.secrets.isEmpty {
                Text("None").font(.caption).foregroundStyle(.tertiary)
            } else {
                SecretChips(names: file.secrets)
            }
        }
    }

    @ViewBuilder
    private var maintenanceSection: some View {
        SidebarSection(title: "Maintenance") {
            VStack(alignment: .leading, spacing: 4) {
                // `claude_md_generated == null` is truthful today, so say so.
                SidebarKeyValue(
                    key: "CLAUDE.md drift",
                    value: file.claudeMdGenerated == nil ? "not generated yet" : "not available yet",
                    placeholder: true
                )
                SidebarKeyValue(key: "Secret sync", value: "not available yet", placeholder: true)
                Text("Available once global config exists.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        SidebarSection(title: "Activity") {
            VStack(alignment: .leading, spacing: 4) {
                SidebarKeyValue(key: "Folder modified", value: SidebarFormat.relativeString(node.lastActivityDate))
                SidebarKeyValue(key: "Tokens consumed", value: "not available yet", placeholder: true)
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        // Visibility now lives in Git; CLAUDE.md in Maintenance; modules aren't
        // a surfaced concept. Only the adoption date remains here — hide the
        // section entirely when there's nothing to show.
        if let adopted = file.adopted {
            SidebarSection(title: "Details") {
                SidebarKeyValue(key: "Adopted", value: adopted)
            }
        }
    }
}

/// Wrapping, quiet monospaced tokens for secret names — names only, never values.
private struct SecretChips: View {
    let names: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

// MARK: - Organizer

private struct OrganizerDetail: View {
    let node: AIControlNode

    var body: some View {
        SidebarScaffold(
            header: SidebarHeader(
                systemImage: "folder",
                isAccent: false,
                name: node.name,
                caption: "Organizer · Under AI Control"
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.children.count == 1 ? "1 project" : "\(node.children.count) projects")
                    .font(.body)
                    .foregroundStyle(.secondary)
                SidebarKeyValue(key: "Most recent", value: SidebarFormat.relativeString(node.lastActivityDate))
                if node.nestedOrganizerWarning {
                    Text("Contains a nested organizer that needs fixing.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Untouched

private struct UntouchedDetail: View {
    let node: AIControlNode
    let onBringUnderControl: (AIControlNode) -> Void

    var body: some View {
        SidebarScaffold(
            header: SidebarHeader(
                systemImage: "folder.badge.questionmark",
                isAccent: false,
                name: node.name,
                caption: "Not under AI Control"
            )
        ) {
            Text("This folder has no AI Control markers. The AI can look at it and decide whether it's a project or an organizer.")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Button("Bring under AI Control") { onBringUnderControl(node) }
                    .buttonStyle(.bordered)
                Text("The full adoption flow arrives with the AI window; for now this reveals the folder in Finder.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            SidebarSection(title: "Details") {
                SidebarKeyValue(key: "Folder modified", value: SidebarFormat.relativeString(node.lastActivityDate))
            }
        }
    }
}

// MARK: - Invalid nested organizer

private struct InvalidNestedDetail: View {
    let node: AIControlNode
    let onLetAIFix: (AIControlNode) -> Void

    var body: some View {
        SidebarScaffold(
            header: SidebarHeader(
                systemImage: "exclamationmark.triangle",
                isAccent: false,
                name: node.name,
                caption: "Nested organizer — not allowed"
            )
        ) {
            Text("An organizer can't live inside another organizer. To fix this, either move this folder out to the root, or move its projects up into the parent organizer and remove its .organize marker.")
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Button("Let AI fix it") { onLetAIFix(node) }
                    .buttonStyle(.bordered)
                Text("The AI will read this folder with a predefined prompt and fix it. That arrives with the AI window; for now this reveals the folder in Finder.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
