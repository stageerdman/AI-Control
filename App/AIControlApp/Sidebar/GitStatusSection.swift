import SwiftUI

/// The sidebar's GitHub section, driven entirely by `.project` (the `github:`
/// URL and `visibility:`) — **no live `git` call per selection**, so clicking
/// between rows is instant. Rich working-tree status (branch, ahead/behind,
/// last commit) belongs to the double-click project view (PROJECT.md §8.3),
/// where it can be read once on open rather than on every dashboard click.
struct GitHubSection: View {
    let githubURL: String?
    let visibility: String?

    var body: some View {
        SidebarSection(title: "GitHub") {
            VStack(alignment: .leading, spacing: 4) {
                if let githubURL, !githubURL.isEmpty, let url = URL(string: githubURL) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text(displayURL(githubURL))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "arrow.up.right").font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    if let visibility, !visibility.isEmpty {
                        Text("\(visibility.capitalized) repository")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    // No URL in .project → nothing is connected, so there's no
                    // public/private to report either.
                    Text("Not connected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func displayURL(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }
}
