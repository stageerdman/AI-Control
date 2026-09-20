import XCTest
@testable import AIControlCore

final class NewProjectValidatorTests: XCTestCase {
    private func validate(_ name: String, _ desc: String = "build a thing", siblings: Set<String> = []) -> [NewProjectValidator.Problem] {
        NewProjectValidator.validate(name: name, description: desc, existingSiblingNames: siblings)
    }

    func testValidInputsHaveNoProblems() {
        XCTAssertTrue(validate("My App").isEmpty)
        XCTAssertTrue(NewProjectValidator.isValid(name: "My App", description: "do things", existingSiblingNames: []))
    }

    func testEmptyNameFlagged() {
        XCTAssertEqual(validate("   "), [.emptyName])
    }

    func testEmptyDescriptionFlagged() {
        XCTAssertEqual(validate("My App", "   "), [.emptyDescription])
    }

    func testInvalidNameCharacters() {
        XCTAssertEqual(validate("a/b"), [.invalidName])
        XCTAssertEqual(validate("."), [.invalidName])
        XCTAssertEqual(validate(".."), [.invalidName])
        XCTAssertEqual(validate(".hidden"), [.invalidName])
    }

    func testNameTakenIsCaseInsensitive() {
        XCTAssertEqual(validate("My App", siblings: ["my app"]), [.nameTaken])
        XCTAssertEqual(validate("Widget", siblings: ["Other", "widget"]), [.nameTaken])
    }

    func testNameNotTakenWhenSiblingsDiffer() {
        XCTAssertTrue(validate("Widget", siblings: ["Other", "Gadget"]).isEmpty)
    }

    func testMultipleProblemsAccumulate() {
        let problems = validate("", "")
        XCTAssertTrue(problems.contains(.emptyName))
        XCTAssertTrue(problems.contains(.emptyDescription))
    }

    func testFolderNameTrims() {
        XCTAssertEqual(NewProjectValidator.folderName(for: "  My App  "), "My App")
    }
}
