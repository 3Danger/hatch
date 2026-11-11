import XCTest
import AppKit
@testable import Hatch

final class HotKeyRecorderTests: XCTestCase {

    func testCmdA() {
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .command, keyCode: 0, characters: "a"), "cmd-a")
    }

    func testCtrlShiftSpace() {
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: [.control, .shift], keyCode: 49, characters: " "), "ctrl-shift-space")
    }

    func testAltTab() {
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .option, keyCode: 48, characters: "\t"), "alt-tab")
    }

    func testNoModifierReturnsNil() {
        XCTAssertNil(KeyChordFormatter.spec(modifiers: [], keyCode: 0, characters: "a"))
    }

    func testCharactersDriveBaseForLetters() {
        // буквы берутся из characters (keyCode здесь используется только для спецклавиш)
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .command, keyCode: 17, characters: "e"), "cmd-e")
    }

    func testDigitKey() {
        // keyCode 19 = '2'
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .command, keyCode: 19, characters: "2"), "cmd-2")
    }

    func testDigitKeyWithoutCharacters() {
        // даже если characters пустой — цифра определяется по keyCode
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .command, keyCode: 19, characters: nil), "cmd-2")
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .command, keyCode: 27, characters: nil), "cmd-0")
    }

    func testEscapeKey() {
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .shift, keyCode: 53, characters: "\u{1b}"), "shift-escape")
    }
}
