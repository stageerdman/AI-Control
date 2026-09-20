import Foundation

/// The app's routine prompts (PROJECT.md §8.6) — the stored text each button
/// sends to a Claude Code session. Every kind has a stable `key` (the filename
/// under `~/.ai-control/prompts/<key>.md`) and a built-in `defaultText` used
/// until the user edits the file. The Settings window (Phase 9) will edit these
/// on disk; the app always reads the file if present and falls back to the
/// default otherwise, so behavior is identical whether or not the repo exists.
enum RoutinePromptKind: String, CaseIterable {
    case stop
    case rebuildClaudeMd = "rebuild-claude-md"
    case syncSecrets = "sync-secrets"
    case newProject = "new-project"
    case adopt
    case newUpdate = "new-update"

    var key: String { rawValue }

    /// Human-facing name for the Settings list.
    var title: String {
        switch self {
        case .stop: return "Stop and save routine"
        case .rebuildClaudeMd: return "Rebuild CLAUDE.md"
        case .syncSecrets: return "Sync secrets"
        case .newProject: return "New project setup"
        case .adopt: return "Bring existing project under AI Control"
        case .newUpdate: return "New update"
        }
    }

    /// The built-in default prompt. Seeded to disk on first-launch bootstrap and
    /// used as the fallback when the file is missing.
    var defaultText: String {
        switch self {
        case .stop:
            return """
            Please wrap up now: bring the current task to a safe stopping point, \
            save any state and notes so we can continue later, update the relevant \
            tracking files, then commit and push everything. We'll come back to this.
            """
        case .rebuildClaudeMd:
            return """
            Rebuild this project's CLAUDE.md from the global modules in \
            ~/.ai-control/modules/. Re-read the modules this project uses (see the \
            `modules:` list in .project), merge them into CLAUDE.md using your \
            judgement for this project, and drop modules that don't apply. Preserve \
            any project-specific rules that were added locally — check the current \
            CLAUDE.md for local additions and keep them. When done, update \
            `claude_md_generated` in .project to today's date and commit.
            """
        case .syncSecrets:
            return """
            Sync this project's .env with the global secrets in ~/.ai-control/.env. \
            For each key this project needs (see `secrets:` in .project), copy the \
            current value from the global .env. Add any newly-needed keys, remove \
            keys no longer used, and keep .env in .gitignore. Never commit secret \
            values. Update the `secrets:` list in .project if it changed, then commit \
            the non-secret changes.
            """
        case .newProject:
            return """
            Set up a new project under AI Control following STRUCTURE.md. Select the \
            relevant global modules from ~/.ai-control/modules/ and compile CLAUDE.md, \
            create the default structure (.project, .gitignore covering .env, .env with \
            the secrets this project needs, updates/, issues.txt), create the first \
            INIT update from the description below, create the GitHub repo with the \
            chosen visibility, connect it, and make the first commit.
            """
        case .adopt:
            return """
            Analyze this folder against STRUCTURE.md and decide whether it is a \
            project or an organizer. Report your verdict and the changes you'd make \
            before touching anything. If I agree, bring it under AI Control: add the \
            right marker (.project or .organize), and for a project generate CLAUDE.md \
            from the global modules and create the standard structure.
            """
        case .newUpdate:
            return """
            Create a new update. Make the folder \
            `updates/YYYY-MM-DD <NAME> - OPEN/` (today's date) with `update v1.md` \
            (goal, phased roadmap, status tracking) and `wiki.md` (decisions and \
            lessons), using the name and definition below. Then commit.
            """
        }
    }
}
