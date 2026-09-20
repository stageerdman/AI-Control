import SwiftUI

/// Small, reusable building blocks for the project sidebar (Phase 3). Kept
/// deliberately minimal and low-chrome to match the dashboard: tertiary
/// all-caps section labels, hairline header rule, quiet key/value rows, and
/// an explicitly *honest* placeholder row for data that later phases will fill
/// in. Space and type weight do the grouping — no boxes or heavy dividers.

/// Shared relative-date formatting, matching the dashboard row's style.
enum SidebarFormat {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func relativeString(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: .now)
    }
}

/// Pinned header: large glyph tying the pane to the row that opened it, name,
/// and one tertiary caption line.
struct SidebarHeader: View {
    let systemImage: String
    let isAccent: Bool
    let name: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(isAccent ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Divider()
        }
    }
}

/// A tertiary, all-caps section label with its content beneath.
struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            content
        }
    }
}

/// A flat key/value line: tertiary key, secondary value.
struct SidebarKeyValue: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// An honestly-empty row for data a later phase will provide: a label with a
/// neutral, *uncolored* "not available yet" note. The absence of a status
/// color is itself the signal — never a faked green/red.
struct SidebarPlaceholderRow: View {
    let label: String
    var note: String = "not available yet"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("— \(note)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Minimal left-to-right wrapping layout, used for secret-name chips. Lays
/// each subview at its ideal size and wraps to a new line when the current one
/// would overflow the proposed width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The sidebar's own empty state — nothing selected.
struct SidebarEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Select a project")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
