import XCTest
@testable import AIControlCore

final class GitStatusParserTests: XCTestCase {
    private let commit = "a1b2c3d\u{0}Add the sidebar\u{0}2026-09-20T12:04:11+02:00"

    func testCleanBranchWithUpstream() {
        let porcelain = """
        # branch.oid a1b2c3d4e5
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        """
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: commit)

        XCTAssertTrue(status.isRepository)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertEqual(status.ahead, 0)
        XCTAssertEqual(status.behind, 0)
        XCTAssertEqual(status.changedFileCount, 0)
        XCTAssertTrue(status.isClean)
        XCTAssertFalse(status.hasUncommittedChanges)
    }

    func testAheadBehindParsed() {
        let porcelain = """
        # branch.head feature
        # branch.upstream origin/feature
        # branch.ab +3 -2
        """
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: commit)

        XCTAssertEqual(status.ahead, 3)
        XCTAssertEqual(status.behind, 2)
        XCTAssertTrue(status.hasUpstream)
    }

    func testChangedAndUntrackedFilesCountTowardDirtyTree() {
        let porcelain = """
        # branch.head main
        1 .M N... 100644 100644 100644 aaa bbb Sources/App.swift
        1 M. N... 100644 100644 100644 ccc ddd README.md
        2 R. N... 100644 100644 100644 eee fff R100 new.swift\told.swift
        u UU N... 100644 100644 100644 100644 ggg hhh iii conflict.swift
        ? untracked.txt
        """
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: commit)

        XCTAssertEqual(status.changedFileCount, 5)
        XCTAssertTrue(status.hasUncommittedChanges)
        XCTAssertFalse(status.isClean)
    }

    func testDetachedHeadHasNilBranch() {
        let porcelain = """
        # branch.oid a1b2c3d4e5
        # branch.head (detached)
        """
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: commit)

        XCTAssertNil(status.branch)
        XCTAssertNil(status.upstream)
        XCTAssertFalse(status.hasUpstream)
    }

    func testNoUpstreamLeavesUpstreamNil() {
        let porcelain = """
        # branch.head main
        """
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: commit)

        XCTAssertEqual(status.branch, "main")
        XCTAssertNil(status.upstream)
        XCTAssertEqual(status.ahead, 0)
        XCTAssertEqual(status.behind, 0)
    }

    func testLastCommitParsed() {
        let porcelain = "# branch.head main"
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: commit)

        XCTAssertEqual(status.lastCommitHash, "a1b2c3d")
        XCTAssertEqual(status.lastCommitSubject, "Add the sidebar")
        XCTAssertNotNil(status.lastCommitDate)
    }

    func testSubjectWithSpacesStaysIntact() {
        let porcelain = "# branch.head main"
        let logLine = "deadbee\u{0}fix: handle spaces, commas — and dashes\u{0}2026-01-02T03:04:05Z"
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: logLine)

        XCTAssertEqual(status.lastCommitSubject, "fix: handle spaces, commas — and dashes")
    }

    func testEmptyLogLineMeansNoCommitsYet() {
        let porcelain = "# branch.head main"
        let status = GitStatusParser.parse(porcelain: porcelain, logLine: "")

        XCTAssertNil(status.lastCommitHash)
        XCTAssertNil(status.lastCommitSubject)
        XCTAssertNil(status.lastCommitDate)
        XCTAssertTrue(status.isRepository)
    }

    func testNotARepositoryConstant() {
        XCTAssertFalse(GitStatus.notARepository.isRepository)
        XCTAssertFalse(GitStatus.notARepository.isClean)
    }
}
