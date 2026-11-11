import XCTest
import SwiftUI
@testable import Hatch

final class ANSITextTests: XCTestCase {

    func testStripRemovesSGR() {
        XCTAssertEqual(ANSIText.strip("\u{1B}[0;31mred\u{1B}[0m plain"), "red plain")
    }

    func testAttributedKeepsTextAndColorsRuns() {
        let text = ANSIText.attributed("\u{1B}[0;1;32mok\u{1B}[0m done")
        XCTAssertEqual(String(text.characters), "ok done")

        let runs = Array(text.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertNotNil(runs[0].foregroundColor, "у «ok» свой цвет")
        XCTAssertNil(runs[1].foregroundColor, "«done» — цвет по умолчанию")
    }

    func testPrefixLines() {
        XCTAssertEqual(ANSIText.prefix("a\nb\nc", lines: 2), "a\nb")
        XCTAssertEqual(ANSIText.prefix("a", lines: 2), "a")
    }
}
