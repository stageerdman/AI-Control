import SwiftUI
import AppKit

extension Color {
    /// The single "an AI needs you" red, used **nowhere else** in the app so its
    /// presence always means exactly one thing — your turn, not an error (Phase
    /// 5.1 UX pass). A tuned crimson (not pure red); deeper + slightly
    /// desaturated in dark mode so it doesn't vibrate.
    static let attentionRed = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.72, green: 0.20, blue: 0.20, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.16, blue: 0.16, alpha: 1)
    })
}

/// Plain button with a subtle white hover wash, for the actions inside the red
/// attention banner.
struct BannerActionButtonStyle: ButtonStyle {
    var circular = false

    func makeBody(configuration: Configuration) -> some View {
        HoverBackground(circular: circular) {
            configuration.label
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }

    private struct HoverBackground<Content: View>: View {
        let circular: Bool
        @ViewBuilder var content: Content
        @State private var hovering = false

        var body: some View {
            content
                .padding(.horizontal, circular ? 0 : 6)
                .frame(minWidth: circular ? 22 : 0, minHeight: circular ? 22 : 20)
                .background {
                    let shape = RoundedRectangle(cornerRadius: circular ? 11 : 4)
                    shape.fill(Color.white.opacity(hovering ? 0.15 : 0))
                }
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
