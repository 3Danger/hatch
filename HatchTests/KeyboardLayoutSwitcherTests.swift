import XCTest
@testable import Hatch

/// Тесты на подставном источнике ввода: настоящую раскладку пользователя тесты не трогают.
final class KeyboardLayoutSwitcherTests: XCTestCase {

    private final class FakeBackend: InputSourceBackend {
        var current: String
        let latin: String?
        private let asciiCapable: Set<String>

        init(current: String, latin: String?, asciiCapable: Set<String>) {
            self.current = current
            self.latin = latin
            self.asciiCapable = asciiCapable
        }

        func currentID() -> String? { current }
        func currentIsASCIICapable() -> Bool { asciiCapable.contains(current) }
        func selectASCIICapable() -> Bool {
            guard let latin else { return false }
            current = latin
            return true
        }
        func select(id: String) -> Bool {
            current = id
            return true
        }
    }

    private let russian = "com.apple.keylayout.Russian"
    private let us = "com.apple.keylayout.US"

    private func backend(current: String, latin: String? = "com.apple.keylayout.US") -> FakeBackend {
        FakeBackend(current: current, latin: latin, asciiCapable: [us, "com.apple.keylayout.ABC"])
    }

    func testSwitchesToLatinAndRestores() {
        let fake = backend(current: russian)
        let switcher = KeyboardLayoutSwitcher(backend: fake)

        switcher.switchToLatin()
        XCTAssertEqual(fake.current, us)

        switcher.restore()
        XCTAssertEqual(fake.current, russian, "панель скрыта — прежняя раскладка вернулась")
    }

    func testAlreadyLatinIsLeftAlone() {
        let fake = backend(current: us)
        let switcher = KeyboardLayoutSwitcher(backend: fake)

        switcher.switchToLatin()
        switcher.restore()
        XCTAssertEqual(fake.current, us)
    }

    /// Пользователь сам сменил раскладку, пока панель открыта, — при скрытии её не трогаем.
    func testUserChoiceIsNotOverridden() {
        let fake = backend(current: russian)
        let switcher = KeyboardLayoutSwitcher(backend: fake)

        switcher.switchToLatin()
        fake.current = "com.apple.keylayout.Ukrainian"
        switcher.restore()
        XCTAssertEqual(fake.current, "com.apple.keylayout.Ukrainian")
    }

    /// Повторный фокус (свернули блок, вернулись в поле) — вернём всё равно исходную раскладку.
    func testRepeatedSwitchKeepsOriginal() {
        let fake = backend(current: russian)
        let switcher = KeyboardLayoutSwitcher(backend: fake)

        switcher.switchToLatin()
        fake.current = russian // пользователь вернул русскую, чтобы набрать текст
        switcher.switchToLatin() // курсор снова в поле
        switcher.restore()
        XCTAssertEqual(fake.current, russian)
    }

    /// Латинских раскладок нет — ничего не ломаем.
    func testNoLatinLayout() {
        let fake = backend(current: russian, latin: nil)
        let switcher = KeyboardLayoutSwitcher(backend: fake)

        switcher.switchToLatin()
        switcher.restore()
        XCTAssertEqual(fake.current, russian)
    }
}
