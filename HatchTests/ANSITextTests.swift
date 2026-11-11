import XCTest
import SwiftUI
import AppKit
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

    /// Тот же текст — из кеша (повторная перерисовка не раскрашивает заново); новый текст — заново.
    func testCacheReturnsSameResultAndSeesNewText() {
        let text = "\u{1B}[0;31mcached-\(UUID().uuidString)\u{1B}[0m"
        let first = ANSIText.attributed(text)
        XCTAssertEqual(ANSIText.attributed(text), first)
        XCTAssertNotEqual(String(ANSIText.attributed(text + "\nmore").characters), String(first.characters))
    }

    /// Для нативного текстового поля: тот же текст, цвет — атрибутом AppKit.
    func testNSAttributedKeepsTextAndColor() {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let text = ANSIText.nsAttributed("\u{1B}[0;32mok\u{1B}[0m done", font: font)
        XCTAssertEqual(text.string, "ok done")
        let okColor = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let doneColor = text.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(okColor)
        XCTAssertNotEqual(okColor, doneColor)
    }

    func testPrefixLines() {
        XCTAssertEqual(ANSIText.prefix("a\nb\nc", lines: 2), "a\nb")
        XCTAssertEqual(ANSIText.prefix("a", lines: 2), "a")
    }
}
