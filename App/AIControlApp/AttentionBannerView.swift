import SwiftUI

/// The thin red banner across the top of the window when an AI needs attention
/// (Phase 5.1). Consolidated — one banner regardless of how many projects are
/// waiting: "Go there" for a single project, "Show" to jump to the dashboard
/// where every awaiting row glows. Full-bleed, 28pt, pushes content down.
struct AttentionBannerView: View {
    let count: Int
    /// Name shown when exactly one project is waiting.
    let primaryName: String
    /// "Go there" (one project) / "Show" (several).
    let onPrimary: () -> Void
    /// The X — dismisses the banner for this awaiting episode (the glow stays).
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.right.fill") // same glyph as the row mark → one signal
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button(action: onPrimary) {
                Text(primaryLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(BannerActionButtonStyle())

            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 14)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(BannerActionButtonStyle(circular: true))
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.attentionRed)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.15)).frame(height: 0.5)
        }
    }

    private var message: String {
        count == 1
            ? "\(primaryName) is waiting for your reply"
            : "\(count) projects are waiting for you"
    }

    private var primaryLabel: String { count == 1 ? "Go there" : "Show" }
}
