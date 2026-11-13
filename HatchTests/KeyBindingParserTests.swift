import XCTest
@testable import Hatch

final class KeyBindingParserTests: XCTestCase {

    func testParseDefaultCtrlSpace() {
        let binding = KeyBindingParser.parse("ctrl-space")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.keyCode, KeyBindingParser.spaceKeyCode)
        XCTAssertEqual(binding?.modifiers, CarbonModifiers.control)
    }

    func testParseCmdShiftA() {
        let binding = KeyBindingParser.parse("cmd-shift-a")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.keyCode, 0) // 'a'
        XCTAssertEqual(binding?.modifiers, CarbonModifiers.command | CarbonModifiers.shift)
    }

    func testParseOptionTab() {
        let binding = KeyBindingParser.parse("alt-tab")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.keyCode, KeyBindingParser.tabKeyCode)
        XCTAssertEqual(binding?.modifiers, CarbonModifiers.option)
    }

    func testParseEmptyNil() {
        XCTAssertNil(KeyBindingParser.parse(""))
    }

    func testParseNoKeyNil() {
        XCTAssertNil(KeyBindingParser.parse("cmd"))
    }

    func testParseTwoKeysNil() {
        XCTAssertNil(KeyBindingParser.parse("cmd-space-a"))
    }

    func testParseUnknownKeyNil() {
        XCTAssertNil(KeyBindingParser.parse("cmd-привет"))
    }

    func testParseCaseInsensitive() {
        XCTAssertNotNil(KeyBindingParser.parse("CTRL-Space"))
    }

    func testParseDigit() {
        let b = KeyBindingParser.parse("cmd-shift-2")
        XCTAssertNotNil(b)
        XCTAssertEqual(b?.keyCode, 19) // '2'
        XCTAssertEqual(b?.modifiers, CarbonModifiers.command | CarbonModifiers.shift)
    }

    func testParseZero() {
        XCTAssertEqual(KeyBindingParser.parse("ctrl-0")?.keyCode, 29)
        XCTAssertEqual(KeyBindingParser.parse("cmd-shift-4")?.keyCode, 21)
        XCTAssertEqual(KeyBindingParser.parse("cmd-shift-5")?.keyCode, 23)
    }
}
