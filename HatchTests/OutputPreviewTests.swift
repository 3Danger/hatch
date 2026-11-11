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
}
