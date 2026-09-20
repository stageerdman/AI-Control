import XCTest
@testable import AIControlCore

final class GlobalConfigReaderTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("ai-control-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let root, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    private func makeDir(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, to relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testMissingRootReportsDoesNotExist() {
        let config = GlobalConfigReader().read(root: root)
        XCTAssertFalse(config.exists)
        XCTAssertTrue(config.modules.isEmpty)
        XCTAssertTrue(config.prompts.isEmpty)
        XCTAssertTrue(config.secretNames.isEmpty)
    }

    func testEmptyRootExistsButHasNothing() throws {
        _ = try makeDir(".")
        let config = GlobalConfigReader().read(root: root)
        XCTAssertTrue(config.exists)
        XCTAssertTrue(config.modules.isEmpty)
    }

    func testReadsModulesSortedByName() throws {
        try write("# UX", to: "modules/UX.md")
        try write("# Coding", to: "modules/CODING.md")
        try write("not markdown", to: "modules/notes.txt")
        let config = GlobalConfigReader().read(root: root)
        XCTAssertEqual(config.modules.map(\.name), ["CODING", "UX"])
        XCTAssertTrue(config.modules.allSatisfy { $0.modifiedAt.timeIntervalSince1970 > 0 })
    }

    func testModuleModifiedDatesLookup() throws {
        try write("# UX", to: "modules/UX.md")
        let config = GlobalConfigReader().read(root: root)
        XCTAssertNotNil(config.moduleModifiedDates["UX"])
        XCTAssertNil(config.moduleModifiedDates["CODING"])
    }

    func testReadsWikiUsageDescription() throws {
        try write("# GoHighLevel\n\nHow we control the GoHighLevel CRM API.\n\nBody...", to: "wiki/GoHighLevel.md")
        try write("Just a first line description.", to: "wiki/Stripe.md")
        let config = GlobalConfigReader().read(root: root)
        let ghl = config.wikiPages.first { $0.name == "GoHighLevel" }
        XCTAssertEqual(ghl?.usageDescription, "How we control the GoHighLevel CRM API.")
        let stripe = config.wikiPages.first { $0.name == "Stripe" }
        XCTAssertEqual(stripe?.usageDescription, "Just a first line description.")
    }

    func testReadsPromptsByKey() throws {
        try write("Wrap everything up and commit.\n", to: "prompts/stop.md")
        try write("Rebuild CLAUDE.md from the modules.", to: "prompts/rebuild.md")
        let config = GlobalConfigReader().read(root: root)
        XCTAssertEqual(config.prompt("stop"), "Wrap everything up and commit.")
        XCTAssertEqual(config.prompt("rebuild"), "Rebuild CLAUDE.md from the modules.")
        XCTAssertNil(config.prompt("missing"))
    }

    func testReadsSecretNamesOnly() throws {
        try write(
            """
            # global secrets
            OPENAI_API_KEY=sk-secret-value
            export GHL_API_KEY = another-value

            EMPTY_LINE_ABOVE=1
            OPENAI_API_KEY=duplicate-ignored
            """,
            to: ".env"
        )
        let config = GlobalConfigReader().read(root: root)
        XCTAssertEqual(config.secretNames, ["OPENAI_API_KEY", "GHL_API_KEY", "EMPTY_LINE_ABOVE"])
        // Values must never leak into the model.
        XCTAssertFalse(config.secretNames.contains { $0.contains("sk-secret-value") })
    }
}
