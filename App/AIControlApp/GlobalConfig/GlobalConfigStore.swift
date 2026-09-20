import Foundation
import Combine
import AIControlCore

/// App-side owner of the global configuration repo (`~/.ai-control/`, PROJECT.md
/// §6). Reads a `GlobalConfig` snapshot via the core `GlobalConfigReader`,
/// re-reads on demand (the app calls `reload()` when it becomes active or after
/// a project rebuild rewrites `.project`), resolves routine-prompt text (stored
/// file → built-in default), and can scaffold the repo skeleton on first launch.
///
/// It never authors module or wiki *content* — that is the AI's job (principle
/// 2/7). Skeleton creation only lays down empty structure, the editable routine
/// prompts, an empty `.env`, and the wiki search script.
///
/// Not `@MainActor`-isolated so the session store (which resolves prompt text
/// from its own main-thread callbacks) can read it synchronously; all mutations
/// happen on the main thread via the view, keeping `@Published` publishes safe.
final class GlobalConfigStore: ObservableObject {
    @Published private(set) var config: GlobalConfig

    private let reader = GlobalConfigReader()
    private let fileManager = FileManager.default
    let root: URL

    init() {
        root = GlobalConfigLocator.rootURL()
        config = reader.read(root: root)
    }

    func reload() {
        config = reader.read(root: root)
    }

    /// Whether the repo directory exists at all.
    var isSetUp: Bool { config.exists }
    /// Whether any modules have been authored (drift is uncomputable without).
    var hasModules: Bool { !config.modules.isEmpty }

    /// Effective text for a routine prompt: the stored file if present, else the
    /// built-in default. Callers get identical behavior whether or not the repo
    /// has been created yet.
    func promptText(for kind: RoutinePromptKind) -> String {
        config.prompt(kind.key) ?? kind.defaultText
    }

    // MARK: - First-launch skeleton bootstrap

    /// Creates the repo skeleton: `modules/`, `wiki/`, `prompts/` (seeded with
    /// the default routine prompts), an empty `.env`, the wiki search script, a
    /// README, and `git init`. Idempotent — never overwrites an existing file.
    /// Reloads `config` on success. Throws on filesystem errors.
    func createSkeleton() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for sub in [GlobalConfigLocator.subdirectories.modules,
                    GlobalConfigLocator.subdirectories.wiki,
                    GlobalConfigLocator.subdirectories.prompts] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let promptsDir = root.appendingPathComponent(GlobalConfigLocator.subdirectories.prompts, isDirectory: true)
        for kind in RoutinePromptKind.allCases {
            try writeIfAbsent(kind.defaultText + "\n", to: promptsDir.appendingPathComponent("\(kind.key).md"))
        }

        try writeIfAbsent(Self.envTemplate, to: root.appendingPathComponent(GlobalConfigLocator.envFileName))
        try writeIfAbsent(Self.gitignore, to: root.appendingPathComponent(".gitignore"))
        try writeIfAbsent(Self.readme, to: root.appendingPathComponent("README.md"))

        let searchScript = root.appendingPathComponent("search.sh")
        if !fileManager.fileExists(atPath: searchScript.path) {
            try Self.wikiSearchScript.write(to: searchScript, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: searchScript.path)
        }

        gitInit()
        reload()
    }

    private func writeIfAbsent(_ contents: String, to url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Best-effort `git init` — the repo is meant to be version-controlled
    /// (§6), but a missing/failed git must not block skeleton creation.
    private func gitInit() {
        guard !fileManager.fileExists(atPath: root.appendingPathComponent(".git").path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init", "-q"]
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Seed content

    private static let envTemplate = """
    # AI Control — global secrets and variables (PROJECT.md §6.5).
    # KEY=value per line. This file holds real values, so keep this repo PRIVATE.
    # Projects receive only the keys they need, synced by the AI — never by hand.

    """

    private static let gitignore = """
    .DS_Store
    """

    private static let readme = """
    # AI Control — global config

    Shared configuration for every project under AI Control (see PROJECT.md §6).

    - `modules/` — the coding/workflow/UX/structure modules the AI merges into
      each project's `CLAUDE.md`. **Authored by the AI**, not templated by the app.
    - `wiki/` — knowledge pages (one per topic). Each starts with a one-line usage
      description so `search.sh` and any AI can find it.
    - `prompts/` — the editable routine prompts the app's buttons send to Claude.
    - `.env` — global secrets. Keep this repo private.
    - `search.sh` — searches the wiki by keyword.

    This skeleton was created by the app. The modules are authored later by the AI.
    """

    private static let wikiSearchScript = """
    #!/bin/sh
    # Search the AI Control wiki by keyword. Usage: ./search.sh <query>
    # Matches page names, usage descriptions, and body text; prints each hit's
    # path and its usage description (the first non-heading line).
    set -eu
    dir="$(cd "$(dirname "$0")" && pwd)/wiki"
    query="${1:-}"
    if [ -z "$query" ]; then echo "usage: $0 <query>" >&2; exit 2; fi
    [ -d "$dir" ] || { echo "no wiki/ directory yet" >&2; exit 0; }
    for f in "$dir"/*.md; do
      [ -e "$f" ] || continue
      if grep -qi "$query" "$f" 2>/dev/null; then
        desc=$(grep -m1 -vE '^\\s*(#|$)' "$f" 2>/dev/null || true)
        echo "$f"
        [ -n "$desc" ] && echo "    $desc"
      fi
    done
    """
}
