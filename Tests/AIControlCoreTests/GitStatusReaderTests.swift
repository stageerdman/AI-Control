import XCTest
@testable import AIControlCore

/// End-to-end check that the reader drives real `git` and the parser agrees.
/// Skips (rather than fails) when `git` isn't installed, so the pure-parser
/// suite still runs anywhere.
final class GitStatusReaderTests: XCTestCase {
    private let fileManager = FileManager.default
    private var repoURL: URL!
    private let gitPath = "/usr/bin/git"

    override func setUpWithError() throws {
        try XCTSkipUnless(fileManager.isExecutableFile(atPath: gitPath), "git not installed")
        repoURL = fileManager.temporaryDirectory
            .appendingPathComponent("GitStatusReaderTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: repoURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let repoURL { try? fileManager.removeItem(at: repoURL) }
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = repoURL
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testNonRepoFolderReportsNotARepository() {
        let status = GitStatusReader().status(for: repoURL)
        XCTAssertFalse(status.isRepository)
    }

    func testFreshRepoWithOneCommitIsCleanWithLastCommit() throws {
        try git(["init", "-b", "main"])
        try git(["config", "user.email", "test@example.com"])
        try git(["config", "user.name", "Test"])
        try "hello".write(to: repoURL.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."])
        try git(["commit", "-m", "Initial commit"])

        let status = GitStatusReader().status(for: repoURL)

        XCTAssertTrue(status.isRepository)
        XCTAssertEqual(status.branch, "main")
        XCTAssertTrue(status.isClean)
        XCTAssertEqual(status.lastCommitSubject, "Initial commit")
        XCTAssertNotNil(status.lastCommitHash)
        XCTAssertNotNil(status.lastCommitDate)
    }

    func testUntrackedFileMakesTreeDirty() throws {
        try git(["init", "-b", "main"])
        try git(["config", "user.email", "test@example.com"])
        try git(["config", "user.name", "Test"])
        try "x".write(to: repoURL.appendingPathComponent("committed.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."])
        try git(["commit", "-m", "seed"])
        try "y".write(to: repoURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let status = GitStatusReader().status(for: repoURL)

        XCTAssertTrue(status.hasUncommittedChanges)
        XCTAssertEqual(status.changedFileCount, 1)
    }
}
