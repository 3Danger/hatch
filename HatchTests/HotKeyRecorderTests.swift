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
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .command, keyCode: 29, characters: nil), "cmd-0")
        // коды цифр идут не по порядку: 5 — 23, 6 — 22 (раньше ⇧⌘5 записывался как ⇧⌘6)
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: [.command, .shift], keyCode: 23, characters: nil), "cmd-shift-5")
        XCTAssertNil(KeyChordFormatter.spec(modifiers: .command, keyCode: 27, characters: nil), "27 — минус, не цифра")
    }

    func testEscapeKey() {
        XCTAssertEqual(KeyChordFormatter.spec(modifiers: .shift, keyCode: 53, characters: "\u{1b}"), "shift-escape")
    }

    /// Сочетание дерева папок (⌘P) срабатывает и в русской раскладке, где P — это «з».
    func testShortcutMatchesInAnyLayout() {
        XCTAssertTrue(KeyChordFormatter.matches("cmd-p", modifiers: .command, keyCode: 35, characters: "p"))
        XCTAssertTrue(KeyChordFormatter.matches("cmd-p", modifiers: .command, keyCode: 35, characters: "з"))
        XCTAssertFalse(KeyChordFormatter.matches("cmd-p", modifiers: [.command, .shift], keyCode: 35, characters: "p"))
        XCTAssertFalse(KeyChordFormatter.matches("cmd-p", modifiers: .command, keyCode: 31, characters: "o"))
        XCTAssertTrue(KeyChordFormatter.matches("ctrl-alt-t", modifiers: [.control, .option], keyCode: 17, characters: "е"))
    }
}
