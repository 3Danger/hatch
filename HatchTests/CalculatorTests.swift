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

    /// Разряды через пробел: пробел, за которым ровно три цифры; иначе — не число.
    func testThousandsSeparatedBySpaces() {
        XCTAssertEqual(value("1 000 000 / 3")! , 1_000_000.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(value("1 000,5*2"), 2001)
        XCTAssertEqual(value("1\u{00A0}000 + 1"), 1001) // неразрывный пробел из документа
        XCTAssertNil(Calculator.evaluate("2 3"))
        XCTAssertNil(Calculator.evaluate("1 0000 + 1"))
        XCTAssertNil(Calculator.evaluate("1 000 000"), "одно число — не расчёт")
    }

    func testSeparatorAsTyped() {
        XCTAssertEqual(Calculator.separator(in: "11.11*.11"), ".")
        XCTAssertEqual(Calculator.separator(in: "11,11*,11"), ",")
        XCTAssertNil(Calculator.separator(in: "7/2"))
        XCTAssertNil(Calculator.separator(in: "1.5+2,5"))
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.display(1024), "1\u{00A0}024")
        XCTAssertEqual(Calculator.clipboard(1024), "1024")
        XCTAssertEqual(Calculator.display(1024.5, separator: ","), "1\u{00A0}024,5")
        XCTAssertEqual(Calculator.clipboard(1024.5, separator: ","), "1024,5")
        XCTAssertEqual(Calculator.clipboard(0.5), "0.5")
        XCTAssertEqual(Calculator.clipboard(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.clipboard(1.0 / 3), "0.3333333333")
        XCTAssertEqual(Calculator.clipboard(1.2221), "1.2221")
    }
}
