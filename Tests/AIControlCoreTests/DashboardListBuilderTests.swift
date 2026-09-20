import XCTest
@testable import AIControlCore

final class DashboardListBuilderTests: XCTestCase {
    private func makeNode(
        name: String,
        kind: NodeKind,
        date: TimeInterval,
        children: [AIControlNode] = [],
        description: String = ""
    ) -> AIControlNode {
        let url = URL(fileURLWithPath: "/root/\(name)")
        let projectFile = kind == .project ? ProjectFile(name: name, body: description) : nil
        return AIControlNode(
            url: url,
            kind: kind,
            projectFile: projectFile,
            children: children,
            lastActivityDate: Date(timeIntervalSince1970: date)
        )
    }

    // MARK: Browsing (no search query)

    func testTopLevelNodesSortByRecencyDescending() {
        let old = makeNode(name: "old", kind: .project, date: 100)
        let recent = makeNode(name: "recent", kind: .project, date: 300)
        let middle = makeNode(name: "middle", kind: .untouched, date: 200)

        let rows = DashboardListBuilder.build(nodes: [old, recent, middle], expandedIDs: [], searchQuery: "")

        XCTAssertEqual(rows.map(\.node.name), ["recent", "middle", "old"])
        XCTAssertEqual(rows.map(\.depth), [0, 0, 0])
    }

    func testCollapsedOrganizerHidesChildren() {
        let child = makeNode(name: "child", kind: .project, date: 500)
        let organizer = makeNode(name: "organizer", kind: .organizer, date: 500, children: [child])

        let rows = DashboardListBuilder.build(nodes: [organizer], expandedIDs: [], searchQuery: "")

        XCTAssertEqual(rows.map(\.node.name), ["organizer"])
    }

    func testExpandedOrganizerInsertsChildrenBeneathSortedByOwnRecency() {
        let olderChild = makeNode(name: "older-child", kind: .project, date: 100)
        let newerChild = makeNode(name: "newer-child", kind: .project, date: 200)
        let organizer = makeNode(name: "organizer", kind: .organizer, date: 200, children: [olderChild, newerChild])

        let rows = DashboardListBuilder.build(nodes: [organizer], expandedIDs: [organizer.id], searchQuery: "")

        XCTAssertEqual(rows.map(\.node.name), ["organizer", "newer-child", "older-child"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1])
    }

    func testOrganizerRecencyActsAsMaxOfChildrenForTopLevelPlacement() {
        // The organizer's own lastActivityDate (as computed by FolderScanner) already
        // equals the max of its children; this test locks in that the builder trusts
        // that value for top-level ordering rather than recomputing it.
        let child = makeNode(name: "child", kind: .project, date: 900)
        let organizerWithRecentChild = makeNode(name: "recent-organizer", kind: .organizer, date: 900, children: [child])
        let standaloneProject = makeNode(name: "standalone", kind: .project, date: 500)

        let rows = DashboardListBuilder.build(
            nodes: [standaloneProject, organizerWithRecentChild],
            expandedIDs: [],
            searchQuery: ""
        )

        XCTAssertEqual(rows.map(\.node.name), ["recent-organizer", "standalone"])
    }

    // MARK: Search

    func testSearchMatchesProjectNameCaseInsensitively() {
        let match = makeNode(name: "Fathom-Downloader", kind: .project, date: 100)
        let nonMatch = makeNode(name: "other", kind: .project, date: 200)

        let rows = DashboardListBuilder.build(nodes: [match, nonMatch], expandedIDs: [], searchQuery: "fathom")

        XCTAssertEqual(rows.map(\.node.name), ["Fathom-Downloader"])
    }

    func testSearchMatchesProjectDescriptionBody() {
        let match = makeNode(name: "widget", kind: .project, date: 100, description: "Controls the GoHighLevel pipeline")

        let rows = DashboardListBuilder.build(nodes: [match], expandedIDs: [], searchQuery: "pipeline")

        XCTAssertEqual(rows.map(\.node.name), ["widget"])
    }

    func testSearchFlattensMatchingOrganizerWhenExpanded() {
        let child = makeNode(name: "child", kind: .project, date: 100)
        let organizer = makeNode(name: "search-target", kind: .organizer, date: 100, children: [child])

        let rows = DashboardListBuilder.build(nodes: [organizer], expandedIDs: [organizer.id], searchQuery: "search-target")

        XCTAssertEqual(rows.map(\.node.name), ["search-target", "child"])
        XCTAssertEqual(rows.map(\.depth), [0, 0], "search results are flat regardless of nesting")
    }

    func testSearchOnMatchingOrganizerWithoutExpansionOmitsChildren() {
        let child = makeNode(name: "child", kind: .project, date: 100)
        let organizer = makeNode(name: "search-target", kind: .organizer, date: 100, children: [child])

        let rows = DashboardListBuilder.build(nodes: [organizer], expandedIDs: [], searchQuery: "search-target")

        XCTAssertEqual(rows.map(\.node.name), ["search-target"])
    }

    func testSearchAnchorsMatchingChildOfNonMatchingOrganizerWithoutSiblings() {
        let matchingChild = makeNode(name: "needle", kind: .project, date: 100)
        let siblingChild = makeNode(name: "hay", kind: .project, date: 200)
        let organizer = makeNode(name: "organizer", kind: .organizer, date: 200, children: [matchingChild, siblingChild])

        let rows = DashboardListBuilder.build(nodes: [organizer], expandedIDs: [organizer.id], searchQuery: "needle")

        XCTAssertEqual(rows.map(\.node.name), ["needle"], "non-matching organizer and its non-matching sibling must not appear")
    }

    func testSearchDropsOrganizerWithNoMatchingNameOrChildren() {
        let child = makeNode(name: "hay", kind: .project, date: 100)
        let organizer = makeNode(name: "organizer", kind: .organizer, date: 100, children: [child])

        let rows = DashboardListBuilder.build(nodes: [organizer], expandedIDs: [], searchQuery: "needle")

        XCTAssertTrue(rows.isEmpty)
    }

    func testInvalidNestedOrganizerNeverExpandsAndOnlyMatchesByName() {
        let invalid = makeNode(name: "mistake", kind: .invalidNestedOrganizer, date: 100)

        let browsingRows = DashboardListBuilder.build(nodes: [invalid], expandedIDs: [invalid.id], searchQuery: "")
        XCTAssertEqual(browsingRows.map(\.node.name), ["mistake"])

        let searchRows = DashboardListBuilder.build(nodes: [invalid], expandedIDs: [], searchQuery: "mistake")
        XCTAssertEqual(searchRows.map(\.node.name), ["mistake"])
    }

    func testEmptyOrWhitespaceQueryIsTreatedAsBrowsing() {
        let project = makeNode(name: "project", kind: .project, date: 100)

        let rows = DashboardListBuilder.build(nodes: [project], expandedIDs: [], searchQuery: "   ")

        XCTAssertEqual(rows.map(\.node.name), ["project"])
    }
}
