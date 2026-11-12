import XCTest
@testable import Hatch

final class CalculatorTests: XCTestCase {
    private func value(_ text: String) -> Double? {
        if case .value(let v) = Calculator.evaluate(text) { return v }
        return nil
    }

    func testArithmetic() {
        XCTAssertEqual(value("12*3.5"), 42)
        XCTAssertEqual(value("(1200-150)/3"), 350)
        XCTAssertEqual(value("2^10"), 1024)
        XCTAssertEqual(value("1/2"), 0.5)
        XCTAssertEqual(value("2+3*4"), 14)
        XCTAssertEqual(value(" 10 - 3 "), 7)
        XCTAssertEqual(value("1,5*2"), 3)
        XCTAssertEqual(value("6×7"), 42)
        XCTAssertEqual(value("9÷3"), 3)
    }

    func testPowerAndUnaryMinus() {
        XCTAssertEqual(value("2^3^2"), 512) // справа налево
        XCTAssertEqual(value("-2^2"), -4)
        XCTAssertEqual(value("2*-3"), -6)
        XCTAssertEqual(value("2--3"), 5)
    }

    func testPercent() {
        XCTAssertEqual(value("4500*15%"), 675)
        XCTAssertEqual(value("15%"), 0.15)
    }

    /// Одно число, незаконченное выражение и команды — не расчёт.
    func testNotExpressions() {
        for text in ["42", "-5", "(5)", "12*", "1.2.3", "ls -1 | wc -l", "git log", "", "10.0.0.1", "()", "+", "2(3)"] {
            XCTAssertNil(Calculator.evaluate(text), text)
        }
    }

    func testDivisionByZero() {
        XCTAssertEqual(Calculator.evaluate("1/0"), .divisionByZero)
        XCTAssertEqual(Calculator.evaluate("5/(2-2)"), .divisionByZero)
    }

    func testFormatting() {
        let ru = Locale(identifier: "ru_RU")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(Calculator.clipboard(1024, locale: ru), "1024")
        XCTAssertEqual(Calculator.clipboard(1024, locale: en), "1024")
        XCTAssertEqual(Calculator.display(1024, locale: en), "1,024")
        XCTAssertEqual(Calculator.clipboard(0.5, locale: ru), "0,5")
        XCTAssertEqual(Calculator.clipboard(0.5, locale: en), "0.5")
        XCTAssertEqual(Calculator.clipboard(0.1 + 0.2, locale: en), "0.3")
        XCTAssertEqual(Calculator.clipboard(1.0 / 3, locale: en), "0.3333333333")
    }
}
