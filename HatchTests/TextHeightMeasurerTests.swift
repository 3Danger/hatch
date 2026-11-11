import XCTest
import AppKit
@testable import Hatch

/// Высота раскрытого вывода: считается без показанного поля, сразу и одинаково при повторах.
final class TextHeightMeasurerTests: XCTestCase {
    private let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    private func text(lines: Int, width: Int = 10) -> NSAttributedString {
        let body = (1...lines).map { _ in String(repeating: "x", count: width) }.joined(separator: "\n")
        return NSAttributedString(string: body, attributes: [.font: font])
    }

    func testHeightIsKnownBeforeTextIsShown() {
        // раньше до первой подстановки текста в поле высота была 0 — список прыгал и падал
        XCTAssertGreaterThan(TextHeightMeasurer().height(of: text(lines: 50), width: 640), 0)
    }

    func testNarrowerWidthIsNeverLower() {
        // полоса прокрутки сужает поле: высота не должна от этого падать, иначе список колеблется
        let measurer = TextHeightMeasurer()
        let long = text(lines: 30, width: 200)
        let wide = measurer.height(of: long, width: 640)
        let narrow = measurer.height(of: long, width: 623)
        XCTAssertGreaterThanOrEqual(narrow, wide)
        XCTAssertEqual(measurer.height(of: long, width: 640), wide)
    }

    func testNewTextIsMeasuredAgain() {
        let measurer = TextHeightMeasurer()
        let short = measurer.height(of: text(lines: 2), width: 640)
        let tall = measurer.height(of: text(lines: 40), width: 640)
        XCTAssertGreaterThan(tall, short)
    }
}
