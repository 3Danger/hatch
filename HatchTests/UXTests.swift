import XCTest
import SwiftUI
@testable import Hatch

/// Мелочи интерфейса из UX-разбора: счётчик поиска, сокращение пути, подсветка совпадений, шпаргалка.
final class UXTests: XCTestCase {
    func testSearchStatsCountsBlocksAndMatches() {
        let sessions = [Session(command: "ls Hatch", state: .completed), Session(command: "git log", state: .completed),
                        Session(command: "echo", state: .completed)]
        var withOutput = sessions
        withOutput[1].output = "camera on hatch\nhatch, HATCH"
        let stats = SearchStats.count("hatch", in: withOutput)
        XCTAssertEqual(stats.blocks, 2)
        XCTAssertEqual(stats.matches, 4)
        XCTAssertEqual(SearchStats.count("", in: withOutput).blocks, 0)
    }

    func testSearchSummaryPlurals() {
        XCTAssertEqual(SearchStats.summary((1, 1), lang: "ru"), "1 блок · 1 совпадение")
        XCTAssertEqual(SearchStats.summary((2, 3), lang: "ru"), "2 блока · 3 совпадения")
        XCTAssertEqual(SearchStats.summary((5, 11), lang: "ru"), "5 блоков · 11 совпадений")
        XCTAssertEqual(SearchStats.summary((21, 22), lang: "ru"), "21 блок · 22 совпадения")
        XCTAssertEqual(SearchStats.summary((1, 2), lang: "en"), "1 block · 2 matches")
    }

    func testLongPathHidesMiddle() {
        XCTAssertNil(DirectoryBreadcrumbsView.hiddenRange(count: 4), "короткий путь — целиком")
        XCTAssertEqual(DirectoryBreadcrumbsView.hiddenRange(count: 5), 1..<3, "видны первая и две последние")
        XCTAssertEqual(DirectoryBreadcrumbsView.hiddenRange(count: 8), 1..<6)
    }

    func testMarkedHighlightsEveryMatch() {
        let marked = SessionBlockView.marked(AttributedString("Hatch and hatch"), "hatch")
        let lit = marked.runs.filter { $0.backgroundColor != nil }.map { String(marked[$0.range].characters) }
        XCTAssertEqual(lit, ["Hatch", "hatch"])
        XCTAssertEqual(SessionBlockView.marked(AttributedString("abc"), nil).runs.count, 1)
    }

    func testKeysSheetPerMode() {
        let command = KeysSheetView.groups(mode: .command, hotkey: "⌥Space", lang: "ru").flatMap(\.rows).map(\.key)
        XCTAssertTrue(command.contains("⌘R") && command.contains("⌘C"), "клавиши выбранного блока")
        let clipboard = KeysSheetView.groups(mode: .clipboard, hotkey: "⌥Space", lang: "ru").flatMap(\.rows).map(\.key)
        XCTAssertTrue(clipboard.contains("⌘↩") && clipboard.contains("⇧⌘R"))
        XCTAssertFalse(clipboard.contains("⌘R"), "в буфере ⌘R нет — формат на ⇧⌘R")
    }
}
