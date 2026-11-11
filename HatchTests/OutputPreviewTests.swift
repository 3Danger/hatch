import XCTest
@testable import Hatch

final class OutputPreviewTests: XCTestCase {

    private func lines(_ n: Int) -> [String] { (1...n).map { "l\($0)" } }

    func testShortOutputShownWhole() {
        let layout = OutputPreview.layout(lines: lines(5), gap: nil, maxLines: 7)
        XCTAssertEqual(layout.head, lines(5))
        XCTAssertEqual(layout.hidden, 0)
        XCTAssertEqual(layout.tail, [])
    }

    /// Длинный вывод: начало, строка «скрыто N», конец — всего не больше maxLines строк.
    func testLongOutputShowsHeadGapTail() {
        let layout = OutputPreview.layout(lines: lines(100), gap: nil, maxLines: 7)
        XCTAssertEqual(layout.head, ["l1", "l2", "l3"])
        XCTAssertEqual(layout.tail, ["l98", "l99", "l100"])
        XCTAssertEqual(layout.hidden, 94)
    }

    /// Превью работающей команды уже без середины: скрытое складывается.
    func testExistingGapIsCounted() {
        // 5 строк начала, 1000 пропущено, 5 строк конца
        let preview = ["h1", "h2", "h3", "h4", "h5", "t1", "t2", "t3", "t4", "t5"]
        let layout = OutputPreview.layout(lines: preview, gap: OutputGap(after: 5, count: 1000), maxLines: 7)
        XCTAssertEqual(layout.head, ["h1", "h2", "h3"])
        XCTAssertEqual(layout.tail, ["t3", "t4", "t5"])
        XCTAssertEqual(layout.hidden, 1004)
    }

    /// Места хватает на всё, кроме пропущенной середины: она одна и остаётся скрытой.
    func testGapWithRoomForEverythingElse() {
        let preview = ["h1", "h2", "t1", "t2"]
        let layout = OutputPreview.layout(lines: preview, gap: OutputGap(after: 2, count: 50), maxLines: 20)
        XCTAssertEqual(layout.head, ["h1", "h2"])
        XCTAssertEqual(layout.tail, ["t1", "t2"])
        XCTAssertEqual(layout.hidden, 50)
    }

    // MARK: - Перенос длинных строк

    /// Две длинные строки по 3 экранные: в 7 строк влезают целиком, без «скрыто».
    func testWrappedLinesCountAsScreenRows() {
        let layout = OutputPreview.layout(lines: ["a", "b"], gap: nil, maxLines: 7, rows: { _ in 3 })
        XCTAssertEqual(layout.head, ["a", "b"])
        XCTAssertEqual(layout.headRows, [3, 3])
        XCTAssertEqual(layout.hidden, 0)
    }

    /// Строки длиннее места: показаны начало и конец, «скрыто» — в строках вывода, не экранных.
    func testLongWrappedOutputHidesWholeLines() {
        let layout = OutputPreview.layout(lines: lines(10), gap: nil, maxLines: 7, rows: { _ in 2 })
        XCTAssertEqual(layout.head, ["l1", "l2"])
        XCTAssertEqual(layout.headRows, [2, 1]) // вторая обрезана до одной экранной строки
        XCTAssertEqual(layout.tail, ["l9", "l10"])
        XCTAssertEqual(layout.tailRows, [1, 2])
        XCTAssertEqual(layout.hidden, 6)
    }

    /// Скрывать нечего, но строки не влезают: без строки «скрыто», обе видны обрезанными.
    func testClippedWithoutHiddenLinesGivesMarkerRowAway() {
        let layout = OutputPreview.layout(lines: ["a", "b"], gap: nil, maxLines: 7, rows: { _ in 10 })
        XCTAssertEqual(layout.hidden, 0)
        XCTAssertEqual(layout.head, ["a"])
        XCTAssertEqual(layout.headRows, [4])
        XCTAssertEqual(layout.tail, ["b"])
        XCTAssertEqual(layout.tailRows, [3])
    }

    func testWrapBreaksOnWords() {
        let text = "unable to get image apache"
        let rows = OutputWrap.rows(text, columns: 10).map { String(Array(text)[$0]) }
        XCTAssertEqual(rows, ["unable to", "get image", "apache"])
    }

    func testWrapCutsWordLongerThanRow() {
        let text = "/Users/someone/very/long/path"
        let rows = OutputWrap.rows(text, columns: 10).map { String(Array(text)[$0]) }
        XCTAssertEqual(rows, ["/Users/som", "eone/very/", "long/path"])
    }

    func testShortLineIsOneRowAndLimitStopsEarly() {
        XCTAssertEqual(OutputWrap.rows("ls", columns: 80), [0..<2])
        XCTAssertEqual(OutputWrap.rows(String(repeating: "x", count: 100_000), columns: 10, limit: 3).count, 3)
    }
}
