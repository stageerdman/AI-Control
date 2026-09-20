import Foundation

/// Whether a project's generated `CLAUDE.md` is still current with the global
/// modules it was built from (PROJECT.md §6.3). Pure/comparison logic only —
/// the app supplies the parsed inputs and renders the result; the AI does any
/// actual rebuild.
public enum ClaudeMdDriftState: Equatable {
    /// No `claude_md_generated` stamp (or it couldn't be parsed) — CLAUDE.md was
    /// never generated from the global modules.
    case notGenerated
    /// Generated, and no recorded module has changed since. `generatedOn` is the
    /// original stamp string, for display.
    case upToDate(generatedOn: String)
    /// One or more recorded modules changed after generation, and/or some no
    /// longer exist globally. `changed` and `removed` are module names.
    case outOfDate(changed: [String], removed: [String], generatedOn: String)
}

/// Compares a project's `claude_md_generated` stamp against the current global
/// modules to decide whether `CLAUDE.md` is out of date. Stateless.
public enum ClaudeMdDriftDetector {
    /// - Parameters:
    ///   - generatedStamp: the raw `claude_md_generated` value from `.project`
    ///     (an ISO date `2026-09-20` or an ISO datetime); `nil` if absent.
    ///   - recordedModules: the module names the project's `.project` `modules:`
    ///     list records (the modules CLAUDE.md was compiled from).
    ///   - moduleModifiedDates: current global modules → last modification date.
    ///     A recorded module absent from this map is treated as removed.
    public static func evaluate(
        generatedStamp: String?,
        recordedModules: [String],
        moduleModifiedDates: [String: Date]
    ) -> ClaudeMdDriftState {
        guard let stamp = generatedStamp?.trimmingCharacters(in: .whitespaces),
              !stamp.isEmpty,
              let generatedAt = parseGeneratedDate(stamp)
        else {
            return .notGenerated
        }

        var changed: [String] = []
        var removed: [String] = []
        for module in recordedModules {
            guard let modifiedAt = moduleModifiedDates[module] else {
                removed.append(module)
                continue
            }
            if modifiedAt > generatedAt {
                changed.append(module)
            }
        }

        if changed.isEmpty && removed.isEmpty {
            return .upToDate(generatedOn: stamp)
        }
        return .outOfDate(changed: changed, removed: removed, generatedOn: stamp)
    }

    /// Parses the generation stamp into the instant everything up to it was
    /// incorporated. A full datetime is used as-is. A date-only stamp
    /// (`2026-09-20`) is interpreted as the **end of that local day**, so a
    /// module touched earlier the same day it was generated doesn't falsely read
    /// as drift, while a change the next day does.
    static func parseGeneratedDate(_ stamp: String) -> Date? {
        if stamp.contains("T") || stamp.contains(":") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: stamp) { return date }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: stamp) { return date }
        }

        // Date-only: parse Y-M-D and roll to the end of that day, local time.
        let parts = stamp.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 23
        components.minute = 59
        components.second = 59
        return Calendar.current.date(from: components)
    }
}
