import SwiftUI
import AIControlCore

/// One row template, four visual variants driven by `node.kind`, per the
/// list-architecture UX doc: glyph shape is the whole language (filled =
/// project, outline = organizer, badge = untouched, triangle = a mistake to
/// fix) — no extra color-coding beyond the single accent reserved for
/// projects.
struct DashboardRowView: View {
    let row: DashboardRow
    let isExpanded: Bool
    let isCursor: Bool
    let isSelected: Bool
    var isRunning: Bool = false
    /// Running session that has finished responding and is waiting for the user
    /// (PROJECT.md §7/§8.1). Only meaningful when `isRunning`.
    var isAwaitingInput: Bool = false

    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var haloOpacity: Double = 0

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            if row.node.kind == .organizer {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }

            Image(systemName: glyphName)
                .foregroundStyle(row.node.kind == .project ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.node.name)
                    .font(.body)
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if row.node.kind == .project || row.node.kind == .organizer {
                Text(Self.relativeFormatter.localizedString(for: row.node.lastActivityDate, relativeTo: .now))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help(Self.absoluteFormatter.string(from: row.node.lastActivityDate))
            }

            // Running-session indicator (PROJECT.md §8.1). The slot is always
            // reserved (16pt) so rows don't reflow when a session starts/stops
            // or switches between working and awaiting-input. Shape carries the
            // meaning — an accent arrow ("your turn") vs. a calm green dot
            // ("busy") — reusing the app's one sanctioned accent rather than
            // introducing a new alarm color (per the Phase 5 UX pass).
            Group {
                if isRunning && isAwaitingInput {
                    Image(systemName: "arrowshape.right.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .help("Waiting for your reply")
                } else if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .transition(.opacity)
                        .help("Session running")
                }
            }
            .frame(width: 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAwaitingInput)
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(selectionBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isCursor ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // Red attention glow — a soft blurred rim just *outside* the row (drawn
        // after the clip so it can bleed past the edge). Distinct visual
        // register from the flat selection tint and the crisp accent cursor
        // ring, so they never collide (Phase 5.1 UX pass). Governed by the raw
        // awaiting state, not banner dismissal, so it persists as the ambient
        // reminder.
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.attentionRed, lineWidth: 2)
                .blur(radius: 3)
                .opacity(isAwaitingInput ? haloOpacity : 0)
                .padding(-1)
                .allowsHitTesting(false)
        )
        .onChange(of: isAwaitingInput) { _, awaiting in updateHalo(awaiting) }
        .onAppear { if isAwaitingInput { haloOpacity = steadyHalo } }
    }

    /// Steady glow strength once settled — a touch dimmer in dark mode.
    private var steadyHalo: Double { colorScheme == .dark ? 0.32 : 0.40 }

    /// One entry swell (0.40→0.80→0.40) on becoming awaiting, then hold steady —
    /// not a continuous throb (the banner owns the "loud" channel). Reduce Motion
    /// skips the swell.
    private func updateHalo(_ awaiting: Bool) {
        guard awaiting else { haloOpacity = 0; return }
        if reduceMotion { haloOpacity = steadyHalo; return }
        withAnimation(.easeOut(duration: 0.25)) { haloOpacity = 0.80 }
        withAnimation(.easeIn(duration: 0.30).delay(0.25)) { haloOpacity = steadyHalo }
    }

    /// Soft accent tint when the window is key, an even quieter gray
    /// "inactive selection" otherwise — deliberately subtle, not a solid
    /// saturated fill.
    private var selectionBackground: Color {
        guard isSelected else { return .clear }
        return controlActiveState == .key ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12)
    }

    private var isDimmed: Bool {
        row.node.kind == .untouched || row.node.kind == .invalidNestedOrganizer
    }

    private var glyphName: String {
        switch row.node.kind {
        case .project: "folder.fill"
        case .organizer: "folder"
        case .untouched: "folder.badge.questionmark"
        case .invalidNestedOrganizer: "exclamationmark.triangle"
        }
    }

    private var subtitle: String {
        switch row.node.kind {
        case .project:
            let description = row.node.projectFile?.body ?? ""
            return description.isEmpty ? "No description yet" : description
        case .organizer:
            let count = row.node.children.count
            return count == 1 ? "1 project" : "\(count) projects"
        case .untouched:
            return "Not under AI Control"
        case .invalidNestedOrganizer:
            return "Nested organizers aren't allowed — move this out of its parent organizer"
        }
    }
}
