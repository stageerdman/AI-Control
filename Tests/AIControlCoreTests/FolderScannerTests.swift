import XCTest
@testable import AIControlCore

final class FolderScannerTests: XCTestCase {
    private var rootURL: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("AIControlCoreTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: rootURL)
    }

    private func makeDir(_ path: String) throws -> URL {
        let url = rootURL.appendingPathComponent(path)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, to url: URL, named filename: String) throws {
        try contents.write(to: url.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    func testFolderWithProjectMarkerClassifiesAsProjectAndParsesFrontmatter() throws {
        let projectDir = try makeDir("my-project")
        try write("""
        ---
        name: my-project
        visibility: private
        ---
        A test project.
        """, to: projectDir, named: ".project")

        let nodes = FolderScanner().scanRoot(at: rootURL)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].kind, .project)
        XCTAssertEqual(nodes[0].name, "my-project")
        XCTAssertEqual(nodes[0].projectFile?.name, "my-project")
        XCTAssertEqual(nodes[0].projectFile?.visibility, "private")
    }

    func testFolderWithOrganizeMarkerClassifiesAsOrganizerAndListsChildProjects() throws {
        let organizerDir = try makeDir("organizer")
        try write("", to: organizerDir, named: ".organize")

        let childDir = try makeDir("organizer/child-project")
        try write("---\nname: child-project\n---\n", to: childDir, named: ".project")

        let nodes = FolderScanner().scanRoot(at: rootURL)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].kind, .organizer)
        XCTAssertFalse(nodes[0].nestedOrganizerWarning)
        XCTAssertEqual(nodes[0].children.count, 1)
        XCTAssertEqual(nodes[0].children[0].kind, .project)
        XCTAssertEqual(nodes[0].children[0].name, "child-project")
    }

    func testFolderWithNeitherMarkerClassifiesAsUntouched() throws {
        _ = try makeDir("some-random-folder")

        let nodes = FolderScanner().scanRoot(at: rootURL)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].kind, .untouched)
        XCTAssertNil(nodes[0].projectFile)
    }

    func testNestedOrganizerIsFlaggedRatherThanCrashingOrSilentlyNesting() throws {
        let outerDir = try makeDir("outer-organizer")
        try write("", to: outerDir, named: ".organize")

        let innerDir = try makeDir("outer-organizer/inner-organizer")
        try write("", to: innerDir, named: ".organize")

        let nodes = FolderScanner().scanRoot(at: rootURL)

        XCTAssertEqual(nodes.count, 1)
        let outer = nodes[0]
        XCTAssertEqual(outer.kind, .organizer)
        XCTAssertTrue(outer.nestedOrganizerWarning)
        XCTAssertEqual(outer.children.count, 1)
        XCTAssertEqual(outer.children[0].kind, .organizer)
    }

    func testMalformedProjectFileDegradesGracefullyInsteadOfCrashing() throws {
        let projectDir = try makeDir("broken-project")
        try write("this is not valid frontmatter at all", to: projectDir, named: ".project")

        let nodes = FolderScanner().scanRoot(at: rootURL)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].kind, .project)
        XCTAssertNil(nodes[0].projectFile?.name)
        XCTAssertEqual(nodes[0].projectFile?.body, "this is not valid frontmatter at all")
    }

    func testMixedRootSortsByName() throws {
        _ = try makeDir("zeta-untouched")
        let projectDir = try makeDir("alpha-project")
        try write("---\nname: alpha-project\n---\n", to: projectDir, named: ".project")
        let organizerDir = try makeDir("mid-organizer")
        try write("", to: organizerDir, named: ".organize")

        let nodes = FolderScanner().scanRoot(at: rootURL)

        XCTAssertEqual(nodes.map(\.name), ["alpha-project", "mid-organizer", "zeta-untouched"])
    }
}
