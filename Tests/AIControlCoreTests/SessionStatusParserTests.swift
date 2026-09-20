import XCTest
@testable import AIControlCore

final class SessionStatusParserTests: XCTestCase {

    // MARK: - Event → activity mapping

    func testEventMapsToActivity() {
        XCTAssertEqual(SessionActivity(hookEvent: "UserPromptSubmit"), .working)
        XCTAssertEqual(SessionActivity(hookEvent: "SessionStart"), .working)
        XCTAssertEqual(SessionActivity(hookEvent: "Stop"), .awaitingInput)
        XCTAssertEqual(SessionActivity(hookEvent: "Notification"), .awaitingInput)
        XCTAssertEqual(SessionActivity(hookEvent: "SessionEnd"), .stopped)
        XCTAssertEqual(SessionActivity(hookEvent: "PostToolUse"), .unknown)
        XCTAssertEqual(SessionActivity(hookEvent: ""), .unknown)
    }

    // MARK: - Parsing our compact status JSON

    func testParsesCompactStatus() {
        let json = #"{"cwd":"/private/tmp/proj","event":"Stop","state":"awaitingInput","session":"abc-123"}"#
        let status = SessionStatusParser.parse(Data(json.utf8))

        XCTAssertNotNil(status)
        XCTAssertEqual(status?.cwd, "/private/tmp/proj")
        XCTAssertEqual(status?.event, "Stop")
        XCTAssertEqual(status?.sessionID, "abc-123")
        XCTAssertEqual(status?.activity, .awaitingInput)
    }

    func testStopIsAwaitingInputUserPromptIsWorking() {
        let stop = SessionStatusParser.parse(Data(#"{"cwd":"/p","event":"Stop"}"#.utf8))
        let working = SessionStatusParser.parse(Data(#"{"cwd":"/p","event":"UserPromptSubmit"}"#.utf8))

        XCTAssertEqual(stop?.activity, .awaitingInput)
        XCTAssertEqual(working?.activity, .working)
    }

    // MARK: - Accepting Claude Code's native field names

    func testFallsBackToNativeHookFieldNames() {
        // A hook that forwards the raw stdin payload uses hook_event_name /
        // session_id rather than our compact keys.
        let json = #"{"cwd":"/private/tmp/proj","hook_event_name":"UserPromptSubmit","session_id":"xyz"}"#
        let status = SessionStatusParser.parse(Data(json.utf8))

        XCTAssertEqual(status?.event, "UserPromptSubmit")
        XCTAssertEqual(status?.sessionID, "xyz")
        XCTAssertEqual(status?.activity, .working)
    }

    func testCompactEventKeyWinsOverNativeKey() {
        let json = #"{"cwd":"/p","event":"Stop","hook_event_name":"UserPromptSubmit"}"#
        XCTAssertEqual(SessionStatusParser.parse(Data(json.utf8))?.event, "Stop")
    }

    // MARK: - Malformed input returns nil (never crashes)

    func testMalformedInputReturnsNil() {
        XCTAssertNil(SessionStatusParser.parse(Data("not json".utf8)))
        XCTAssertNil(SessionStatusParser.parse(Data("".utf8)))
        XCTAssertNil(SessionStatusParser.parse(Data("[1,2,3]".utf8)))          // not an object
        XCTAssertNil(SessionStatusParser.parse(Data(#"{"event":"Stop"}"#.utf8))) // no cwd
        XCTAssertNil(SessionStatusParser.parse(Data(#"{"cwd":"/p"}"#.utf8)))     // no event
        XCTAssertNil(SessionStatusParser.parse(Data(#"{"cwd":"","event":"Stop"}"#.utf8))) // empty cwd
    }

    func testSessionIDIsOptional() {
        let status = SessionStatusParser.parse(Data(#"{"cwd":"/p","event":"Stop"}"#.utf8))
        XCTAssertNotNil(status)
        XCTAssertNil(status?.sessionID)
    }
}
