import XCTest
@testable import Hatch

final class SessionTests: XCTestCase {

    func testInitialStateRunning() {
        let s = Session(command: "echo hi")
        XCTAssertEqual(s.state, .running)
        XCTAssertTrue(s.state.isActive)
        XCTAssertFalse(s.state.isTerminal)
        XCTAssertNil(s.finishedAt)
    }

    func testAllowedTransitionRunningToCompletedSetsFinishedAt() {
        let s = Session(command: "echo hi")
        guard let completed = s.transitioning(to: .completed) else {
            return XCTFail("transition should be allowed")
        }
        XCTAssertEqual(completed.state, .completed)
        XCTAssertTrue(completed.state.isTerminal)
        XCTAssertNotNil(completed.finishedAt)
    }

    func testInteractivePromotionAllowed() {
        let s = Session(command: "vim")
        XCTAssertNotNil(s.transitioning(to: .interactive))
    }

    func testDisallowedTransitionCompletedToRunning() {
        var s = Session(command: "ls")
        s = s.transitioning(to: .completed)!
        XCTAssertNil(s.transitioning(to: .running))
    }

    func testDisallowedCompletedToInteractive() {
        var s = Session(command: "ls")
        s = s.transitioning(to: .completed)!
        XCTAssertNil(s.transitioning(to: .interactive))
    }

    func testTerminalStatesFlag() {
        XCTAssertTrue(SessionState.completed.isTerminal)
        XCTAssertTrue(SessionState.stopped.isTerminal)
        XCTAssertTrue(SessionState.interrupted.isTerminal)
        XCTAssertFalse(SessionState.running.isTerminal)
        XCTAssertFalse(SessionState.interactive.isTerminal)
    }

    func testTransitionMatrix() {
        // допустимые
        XCTAssertTrue(SessionTransition.isAllowed(from: .running, to: .interactive))
        XCTAssertTrue(SessionTransition.isAllowed(from: .running, to: .completed))
        XCTAssertTrue(SessionTransition.isAllowed(from: .running, to: .stopped))
        XCTAssertTrue(SessionTransition.isAllowed(from: .running, to: .interrupted))
        XCTAssertTrue(SessionTransition.isAllowed(from: .interactive, to: .completed))
        XCTAssertTrue(SessionTransition.isAllowed(from: .interactive, to: .stopped))
        XCTAssertTrue(SessionTransition.isAllowed(from: .interactive, to: .interrupted))
        // недопустимые
        XCTAssertFalse(SessionTransition.isAllowed(from: .completed, to: .running))
        XCTAssertFalse(SessionTransition.isAllowed(from: .completed, to: .interactive))
        XCTAssertFalse(SessionTransition.isAllowed(from: .stopped, to: .running))
        XCTAssertFalse(SessionTransition.isAllowed(from: .interrupted, to: .running))
    }

    func testCodableRoundTrip() throws {
        let original = Session(command: "echo hi",
                               state: .completed,
                               finishedAt: Date(),
                               output: "hi\n",
                               pid: 12,
                               pgid: 12,
                               isPinned: true,
                               exitCode: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
