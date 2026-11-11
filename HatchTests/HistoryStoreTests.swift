import XCTest
@testable import Hatch

final class HistoryStoreTests: XCTestCase {

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
    }

    private func completed(_ command: String) -> Session {
        var s = Session(command: command)
        s.state = .completed
        s.finishedAt = Date()
        return s
    }

    func testCapKeepsAllActiveAndLimitsFinished() {
        var sessions: [Session] = []
        for i in 0..<60 {
            sessions.append(completed("c\(i)"))
        }
        sessions.append(Session(command: "a1"))
        sessions.append(Session(command: "a2"))
        sessions.append(Session(command: "a3"))

        let store = HistoryStore(fileURL: tmpURL(), defaultLimit: 50)
        let capped = store.applyCap(to: sessions, limit: 50)

        XCTAssertEqual(capped.filter { $0.state.isActive }.count, 3)
        XCTAssertEqual(capped.count, 53)
    }

    /// Закреплённые не вытесняются лимитом истории.
    func testCapKeepsPinned() {
        var old = completed("pinned-old")
        old.isPinned = true
        old.createdAt = Date(timeIntervalSinceNow: -1000)
        let sessions = [old] + (0..<5).map { completed("c\($0)") }

        let capped = HistoryStore(fileURL: tmpURL()).applyCap(to: sessions, limit: 2)

        XCTAssertTrue(capped.contains { $0.command == "pinned-old" })
        XCTAssertEqual(capped.filter { !$0.isPinned }.count, 2)
    }

    func testSaveLoadRoundTrip() {
        let url = tmpURL()
        let store = HistoryStore(fileURL: url)
        var sessions = [completed("ls"), completed("pwd"), Session(command: "tail")]
        store.save(sessions)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(Set(loaded.map(\.command)), Set(["ls", "pwd", "tail"]))
    }

    func testLoadEmptyFileReturnsEmpty() {
        let store = HistoryStore(fileURL: tmpURL())
        XCTAssertTrue(store.load().isEmpty)
    }

    func testSaveAppliesLimit() {
        let url = tmpURL()
        let store = HistoryStore(fileURL: url, defaultLimit: 2)
        var sessions = [completed("1"), completed("2"), completed("3"), Session(command: "active")]
        store.save(sessions)
        let loaded = store.load(limit: 2)
        XCTAssertEqual(loaded.count, 3) // 2 завершённых + 1 активная
        XCTAssertEqual(loaded.filter { $0.state.isActive }.count, 1)
    }
}
