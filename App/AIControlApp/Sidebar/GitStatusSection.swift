import SwiftUI
import AIControlCore

/// The sidebar's Git section: the richest *actually-true* data this phase has.
/// `status == nil` means a read is still in flight. This is read-only — the
/// only interactive element is the GitHub link, which opens the browser.
struct GitStatusSection: View {
    let status: GitStatus?
    /// `github:` URL from `.project`, if any.
    let githubURL: String?
    /// Repo `visibility:` from `.project` (e.g. "public"/"private"), if any.
    let visibility: String?

    var body: some View {
        SidebarSection(title: "Git") {
            VStack(alignment: .leading, spacing: 4) {
                switch status {
                case .none:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reading…").font(.caption).foregroundStyle(.tertiary)
                    }
                case .some(let status) where !status.isRepository:
                    Text("Not a git repository")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    githubRow // a folder may declare a github URL even if not cloned as a repo
                    visibilityRow
                case .some(let status):
                    cleanStateRow(status)
                    branchRow(status)
                    aheadBehindRow(status)
                    lastCommitRow(status)
                    githubRow
                    visibilityRow
                }
            }
        }
    }

    @ViewBuilder
    private func cleanStateRow(_ status: GitStatus) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.isClean ? Color.green.opacity(0.7) : Color.orange.opacity(0.8))
                .frame(width: 7, height: 7)
            Text(status.isClean ? "Clean" : changeCountText(status.changedFileCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func changeCountText(_ count: Int) -> String {
        count == 1 ? "1 uncommitted change" : "\(count) uncommitted changes"
    }

    @ViewBuilder
    private func branchRow(_ status: GitStatus) -> some View {
        if let branch = status.branch {
            Text(status.upstream.map { "\(branch) → \($0)" } ?? "\(branch) · no upstream")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("Detached HEAD")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func aheadBehindRow(_ status: GitStatus) -> some View {
        if status.ahead > 0 || status.behind > 0 {
            Text("↑\(status.ahead) ahead · ↓\(status.behind) behind")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func lastCommitRow(_ status: GitStatus) -> some View {
        if let hash = status.lastCommitHash {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hash)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(status.lastCommitSubject ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let date = status.lastCommitDate {
                    Text(SidebarFormat.relativeString(date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .layoutPriority(1)
                }
            }
        } else {
            Text("No commits yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var githubRow: some View {
        if let githubURL, let url = URL(string: githubURL) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(displayURL(githubURL))
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        } else {
            Text("No GitHub URL in .project")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var visibilityRow: some View {
        if let visibility, !visibility.isEmpty {
            Text("\(visibility.capitalized) repository")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func displayURL(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }
}
