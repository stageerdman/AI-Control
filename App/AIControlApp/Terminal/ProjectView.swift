import SwiftUI
import SwiftTerm
import AIControlCore

/// Hosts a `TerminalSession`'s SwiftTerm view inside SwiftUI.
struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        session.terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

/// The double-click project view (PROJECT.md §8.3): an embedded terminal fills
/// the main area, with a "Back to dashboard" control. Going back leaves the
/// session running (the store keeps it alive). Phase 4 shows the terminal and
/// the back control; the recent-updates / issues / New-Update side panel is
/// left for a later phase.
struct ProjectView: View {
    let node: AIControlNode
    @ObservedObject var session: TerminalSession
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalContainerView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label("Dashboard", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                Text(node.name).font(.headline)
                if !session.isRunning {
                    Text(session.exitCode.map { "exited (\($0))" } ?? "stopped")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Balances the leading button so the title stays centered.
            Label("Dashboard", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .hidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
