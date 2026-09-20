import XCTest
@testable import AIControlCore

final class ProjectFileParserTests: XCTestCase {
    func testParsesFullFrontmatterAndBody() {
        let contents = """
        ---
        name: my-project
        github: https://github.com/user/my-project
        visibility: private
        adopted: 2026-09-20
        claude_md_generated: 2026-09-20
        modules: [WORKFLOW, STRUCTURE, CODING]
        secrets: [GHL_API_KEY, OPENAI_API_KEY]
        ---

        Description of the project.
        How to use it.
        """

        let file = ProjectFileParser.parse(contents)

        XCTAssertEqual(file.name, "my-project")
        XCTAssertEqual(file.github, "https://github.com/user/my-project")
        XCTAssertEqual(file.visibility, "private")
        XCTAssertEqual(file.adopted, "2026-09-20")
        XCTAssertEqual(file.claudeMdGenerated, "2026-09-20")
        XCTAssertEqual(file.modules, ["WORKFLOW", "STRUCTURE", "CODING"])
        XCTAssertEqual(file.secrets, ["GHL_API_KEY", "OPENAI_API_KEY"])
        XCTAssertEqual(file.body, "Description of the project.\nHow to use it.")
    }

    func testNullAndEmptyListFieldsBecomeDefaults() {
        let contents = """
        ---
        name: bare-project
        claude_md_generated: null
        modules: []
        secrets: []
        ---
        """

        let file = ProjectFileParser.parse(contents)

        XCTAssertEqual(file.name, "bare-project")
        XCTAssertNil(file.claudeMdGenerated)
        XCTAssertEqual(file.modules, [])
        XCTAssertEqual(file.secrets, [])
    }

    func testInlineCommentsAreStripped() {
        let contents = """
        ---
        secrets: [GHL_API_KEY]   # names only, never values
        ---
        """

        let file = ProjectFileParser.parse(contents)

        XCTAssertEqual(file.secrets, ["GHL_API_KEY"])
    }

    func testMissingFrontmatterDelimitersDegradesToBodyOnly() {
        let contents = "Just some plain text, no frontmatter at all."

        let file = ProjectFileParser.parse(contents)

        XCTAssertNil(file.name)
        XCTAssertEqual(file.modules, [])
        XCTAssertEqual(file.body, contents)
    }

    func testUnclosedFrontmatterDegradesToBodyOnlyWithoutCrashing() {
        let contents = """
        ---
        name: unclosed
        this never closes
        """

        let file = ProjectFileParser.parse(contents)

        XCTAssertNil(file.name)
        XCTAssertEqual(file.body, contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testEmptyStringDoesNotCrash() {
        let file = ProjectFileParser.parse("")

        XCTAssertNil(file.name)
        XCTAssertEqual(file.body, "")
    }
}
