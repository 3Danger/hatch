import XCTest
@testable import Hatch

final class HistoryNavigatorTests: XCTestCase {

    private let entries = [
        HistoryNavigator.Entry(id: UUID(), command: "ls -la"),
        HistoryNavigator.Entry(id: UUID(), command: "git status"),
        HistoryNavigator.Entry(id: UUID(), command: "pwd"),
    ]

    func testOlderStartsFromFirstBlock() {
        var nav = HistoryNavigator()
        XCTAssertEqual(nav.older(entries: entries, current: "draft"), "ls -la")
        XCTAssertEqual(nav.selectedID, entries[0].id)
    }

    func testOlderWalksDownAndStopsAtLast() {
        var nav = HistoryNavigator()
        _ = nav.older(entries: entries, current: "")
        XCTAssertEqual(nav.older(entries: entries, current: "ls -la"), "git status")
        XCTAssertEqual(nav.older(entries: entries, current: "git status"), "pwd")
        XCTAssertNil(nav.older(entries: entries, current: "pwd"), "ниже последнего блока идти некуда")
        XCTAssertEqual(nav.selectedID, entries[2].id)
    }

    func testNewerGoesBackAndRestoresDraft() {
        var nav = HistoryNavigator()
        _ = nav.older(entries: entries, current: "my draft")
        _ = nav.older(entries: entries, current: "ls -la")
        XCTAssertEqual(nav.newer(), "ls -la")
        XCTAssertEqual(nav.newer(), "my draft", "выше первого блока возвращается введённый текст")
        XCTAssertNil(nav.selectedID)
        XCTAssertFalse(nav.isNavigating)
    }

    func testNewerWithoutNavigationIsIgnored() {
        var nav = HistoryNavigator()
        XCTAssertNil(nav.newer())
    }

    func testEmptyHistoryIsIgnored() {
        var nav = HistoryNavigator()
        XCTAssertNil(nav.older(entries: [], current: "x"))
        XCTAssertFalse(nav.isNavigating)
    }

    /// Порядок фиксируется на старте навигации: перестройка списка (команда завершилась) не сбивает шаги.
    func testSnapshotIsStableDuringNavigation() {
        var nav = HistoryNavigator()
        _ = nav.older(entries: entries, current: "")
        let reordered = Array(entries.reversed())
        XCTAssertEqual(nav.older(entries: reordered, current: "ls -la"), "git status")
    }

    func testResetExitsNavigation() {
        var nav = HistoryNavigator()
        _ = nav.older(entries: entries, current: "")
        nav.reset()
        XCTAssertFalse(nav.isNavigating)
        XCTAssertEqual(nav.older(entries: entries, current: ""), "ls -la")
    }
}
