import XCTest
import SwiftUI
@testable import Hatch

/// После закрытия всплывающего окна (дерево папок, избранное) клавиатура снова в поле ввода.
/// На настоящей панели: фокус терялся из-за её настроек, а не из-за содержимого.
@MainActor
final class FocusReturnTests: XCTestCase {
    private final class NoHotKeys: HotKeyDelegate { func hotKeyPressed() {} }

    private var controller: FloatingWindowController?

    override func tearDown() {
        controller?.hide()
        controller = nil
        super.tearDown()
    }

    private func spin(_ seconds: TimeInterval = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { spin(0.05) }
    }

    /// Через приложение: так нажатие видят мониторы клавиш панели (⌘1, ⌘E).
    private func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = [], to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                     isARepeat: false, keyCode: code)!
        NSApp.sendEvent(event)
        spin()
    }

    /// Поле ввода — первый ответчик панели (редактор поля).
    private func inputHasFocus(_ window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    private func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let found = textField(in: sub) { return found } }
        return nil
    }

    /// Панель Hatch, как при запуске, с фокусом в поле ввода.
    private func showPanel() throws -> NSWindow {
        ShellTestIsolation.apply()
        let defaults = UserDefaults(suiteName: "FocusReturnTests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.toggleFavoriteDirectory("/usr") // чтобы избранное было не пустым
        let store = SessionStore(history: HistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-\(UUID().uuidString).json")))
        let runner = ProcessRunner(sessionStore: store, settings: settings)
        let root = LauncherRootView().environment(store).environment(runner).environment(settings)
            .environment(HotKeyController(delegate: NoHotKeys()))
        let controller = FloatingWindowController(rootView: root, defaults: defaults)
        self.controller = controller
        controller.show()
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is LauncherPanel && $0.isVisible })
        spin(0.5)
        // приложение под тестами не активно, и SwiftUI сам фокус не ставит — ставим, как при показе
        if !inputHasFocus(panel), let field = textField(in: panel.contentView!) { panel.makeFirstResponder(field) }
        wait { self.inputHasFocus(panel) }
        XCTAssertTrue(inputHasFocus(panel), "до всплывающего окна фокус в поле")
        return panel
    }

    private func assertEscapeReturnsFocus(open code: UInt16, _ chars: String, _ what: String) throws {
        let panel = try showPanel()
        key(code, chars, .command, to: panel)
        wait { panel.childWindows?.count == 1 }
        let popup = try XCTUnwrap(panel.childWindows?.first, "\(what) открылось")
        key(53, "\u{1b}", to: popup)
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "\(what) закрылось")
        wait { self.inputHasFocus(panel) }
        XCTAssertTrue(inputHasFocus(panel), "после Esc (\(what)) фокус в поле: \(String(describing: panel.firstResponder))")
    }

    func testEscapeFromFolderTreeReturnsFocusToInput() throws {
        try assertEscapeReturnsFocus(open: 18, "1", "дерево папок") // ⌘1
    }

    func testEscapeFromFavoritesReturnsFocusToInput() throws {
        try assertEscapeReturnsFocus(open: 14, "e", "избранное") // ⌘E
    }
}
