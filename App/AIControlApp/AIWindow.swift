import SwiftUI
import AIControlCore

/// The dashboard AI window (PROJECT.md §8.4): a persistent, non-modal Claude
/// session rooted at the connected root folder, for general questions and for
/// analyzing/adopting untouched or invalid folders. Distinct from per-project
/// sessions (it never pins or notifies — it's in `globalSessionURLs`). Opened
/// from the "AI" menu and auto-raised whenever an AI action hands it a folder.
struct AIWindow: View {
    static let windowID = "ai-window"

    @ObservedObject var sessionStore: TerminalSessionStore
    @ObservedObject var rootFolderStore: RootFolderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let root = rootFolderStore.rootURL {
                header(root: root)
                Divider()
                TerminalContainerView(session: sessionStore.aiWindowSession(rootURL: root))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    systemImage: "sparkles",
                    title: "Connect a root folder first",
                    message: "The AI session runs at your root folder. Choose one on the dashboard, then reopen this window."
                )
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }

    private func header(root: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarHeader(
                systemImage: "sparkles",
                isAccent: true,
                name: "AI",
                caption: "General questions and folder analysis, at \(root.path)"
            )
            if let ref = sessionStore.aiReference {
                HStack(spacing: 6) {
                    Text("Reference:").font(.caption).foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        Image(systemName: "folder").font(.caption2)
                        Text(ref.name).font(.caption.monospaced())
                        Button { sessionStore.clearAIReference() } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .help(ref.path)
                    Spacer()
                }
            } else {
                Text("Right-click any folder and choose Ask AI to pull it in as a reference.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding([.horizontal, .top], 16)
        .padding(.bottom, 8)
    }
}
