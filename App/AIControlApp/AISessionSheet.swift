import SwiftUI

/// A dedicated terminal sheet for a one-off AI task (adopt an untouched folder,
/// fix an invalid organizer, or ask about a folder — PROJECT.md §8.4/§9.3). Each
/// runs its **own** Claude session in the target folder, so it never borrows a
/// project's terminal. The session survives (held by the store); Done just
/// dismisses the sheet and lets the dashboard rescan.
struct AISessionSheet: View {
    @ObservedObject var session: TerminalSession
    let title: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: "sparkles").font(.headline)
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
