import SwiftUI

/// A slim, neutral setup strip shown at the top of the dashboard only while the
/// global config repo (`~/.ai-control/`) doesn't exist yet (PROJECT.md §6, §9.1).
/// Deliberately NOT the `attentionRed` banner — that hue is reserved for
/// awaiting-input; this is quiet setup guidance, not an alarm. It disappears
/// permanently once the skeleton exists.
struct GlobalConfigBanner: View {
    /// Opens the Global Config window rather than creating silently — the create
    /// action lives in that window where its result stays visible.
    let onSetUp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text("Global config isn't set up. Projects share coding principles, workflow rules and secrets from ~/.ai-control/.")
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Set up…", action: onSetUp)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}
