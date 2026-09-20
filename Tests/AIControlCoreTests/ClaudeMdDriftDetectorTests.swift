import XCTest
@testable import AIControlCore

final class ClaudeMdDriftDetectorTests: XCTestCase {
    /// Builds a local date at the given Y-M-D and time, matching the calendar
    /// `parseGeneratedDate` uses.
    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testNilStampIsNotGenerated() {
        XCTAssertEqual(
            ClaudeMdDriftDetector.evaluate(generatedStamp: nil, recordedModules: ["UX"], moduleModifiedDates: ["UX": date(2026, 9, 20)]),
            .notGenerated
        )
    }

    func testEmptyOrGarbageStampIsNotGenerated() {
        XCTAssertEqual(ClaudeMdDriftDetector.evaluate(generatedStamp: "  ", recordedModules: [], moduleModifiedDates: [:]), .notGenerated)
        XCTAssertEqual(ClaudeMdDriftDetector.evaluate(generatedStamp: "not-a-date", recordedModules: [], moduleModifiedDates: [:]), .notGenerated)
    }

    func testModuleChangedNextDayIsOutOfDate() {
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: "2026-09-20",
            recordedModules: ["UX", "CODING"],
            moduleModifiedDates: ["UX": date(2026, 9, 21), "CODING": date(2026, 9, 1)]
        )
        XCTAssertEqual(state, .outOfDate(changed: ["UX"], removed: [], generatedOn: "2026-09-20"))
    }

    func testModuleTouchedEarlierSameDayIsNotDrift() {
        // Date-only stamp is treated as end-of-day, so a module modified earlier
        // the same day it was generated must not read as drift.
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: "2026-09-20",
            recordedModules: ["UX"],
            moduleModifiedDates: ["UX": date(2026, 9, 20, 9, 30)]
        )
        XCTAssertEqual(state, .upToDate(generatedOn: "2026-09-20"))
    }

    func testAllModulesOlderIsUpToDate() {
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: "2026-09-20",
            recordedModules: ["UX", "CODING"],
            moduleModifiedDates: ["UX": date(2026, 9, 10), "CODING": date(2026, 9, 19)]
        )
        XCTAssertEqual(state, .upToDate(generatedOn: "2026-09-20"))
    }

    func testRecordedModuleMissingGloballyIsRemoved() {
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: "2026-09-20",
            recordedModules: ["UX", "GONE"],
            moduleModifiedDates: ["UX": date(2026, 9, 10)]
        )
        XCTAssertEqual(state, .outOfDate(changed: [], removed: ["GONE"], generatedOn: "2026-09-20"))
    }

    func testChangedAndRemovedTogether() {
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: "2026-09-20",
            recordedModules: ["UX", "GONE", "CODING"],
            moduleModifiedDates: ["UX": date(2026, 9, 25), "CODING": date(2026, 9, 1)]
        )
        XCTAssertEqual(state, .outOfDate(changed: ["UX"], removed: ["GONE"], generatedOn: "2026-09-20"))
    }

    func testNoRecordedModulesIsUpToDate() {
        // Nothing to compare against → not out of date.
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: "2026-09-20",
            recordedModules: [],
            moduleModifiedDates: ["UX": date(2026, 9, 25)]
        )
        XCTAssertEqual(state, .upToDate(generatedOn: "2026-09-20"))
    }

    func testDatetimeStampUsesExactInstant() {
        // A module modified 3 hours after a precise generation datetime is drift,
        // even though it's the same calendar day.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let generated = "2026-09-20T09:00:00Z"
        let moduleModified = iso.date(from: "2026-09-20T12:00:00Z")!
        let state = ClaudeMdDriftDetector.evaluate(
            generatedStamp: generated,
            recordedModules: ["UX"],
            moduleModifiedDates: ["UX": moduleModified]
        )
        XCTAssertEqual(state, .outOfDate(changed: ["UX"], removed: [], generatedOn: generated))
    }
}
