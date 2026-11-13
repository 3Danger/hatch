import XCTest
import SwiftUI
import VisionKit
@testable import Hatch

/// После закрытия всплывающего окна (дерево папок, избранное) клавиатура снова в поле ввода.
/// На настоящей панели: фокус терялся из-за её настроек, а не из-за содержимого.
@MainActor
final class FocusReturnTests: XCTestCase {
    private final class NoHotKeys: HotKeyDelegate { func hotKeyPressed() {} }

    private var controller: FloatingWindowController?
    private var store: SessionStore!
    private var clipboard: ClipboardHistory!
    private var settings: SettingsStore!

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

    private var runner: ProcessRunner?

    /// Панель Hatch, как при запуске, с фокусом в поле ввода.
    private func showPanel() throws -> NSWindow {
        ShellTestIsolation.apply()
        let defaults = UserDefaults(suiteName: "FocusReturnTests.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.toggleFavoriteDirectory("/usr") // чтобы избранное было не пустым
        settings.toggleFavoriteDirectory("/tmp")
        self.settings = settings
        let store = SessionStore(history: HistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-\(UUID().uuidString).json")))
        let clipboard = ClipboardHistory(fileURL: nil, imagesDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-images-\(UUID().uuidString)"))
        self.store = store
        self.clipboard = clipboard
        let runner = ProcessRunner(sessionStore: store, settings: settings)
        self.runner = runner
        let root = LauncherRootView().environment(store).environment(runner).environment(settings)
            .environment(HotKeyController(delegate: NoHotKeys()))
            .environment(clipboard)
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

    /// Команда спросила и ждёт ответа — её блок раскрывается, клавиатура в её терминале.
    func testCommandWaitingForInputExpandsAndTakesKeyboard() throws {
        let panel = try showPanel()
        let runner = try XCTUnwrap(runner)
        runner.run(command: "printf 'Continue? [y/N] '; read answer")
        let deadline = Date().addingTimeInterval(5)
        while !(panel.firstResponder is SessionTerminalView), Date() < deadline { spin(0.05) }
        var trace: [String] = []
        for _ in 0..<30 { // 1,5 с: фокус не должен уйти после раскрытия
            spin(0.05)
            let name = panel.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            if trace.last != name { trace.append(name) }
        }
        XCTAssertEqual(trace, ["SessionTerminalView"], "клавиатура остаётся в терминале")
        XCTAssertNotNil(runner.inputRequest, "вопрос замечен")
        XCTAssertTrue(panel.firstResponder is SessionTerminalView,
                      "клавиатура в терминале блока: \(String(describing: panel.firstResponder))")
        if let id = runner.inputRequest?.sessionID { runner.stop(sessionID: id) }
    }

    // MARK: - Скрытие панели и буфер

    /// ⌘Q и ⌘W (без раскрытого блока) только скрывают панель; Hatch продолжает работать.
    func testCommandQAndWHidePanel() throws {
        for (code, chars) in [(UInt16(12), "q"), (UInt16(13), "w")] {
            let panel = try showPanel()
            key(code, chars, .command, to: panel)
            wait { !panel.isVisible }
            XCTAssertFalse(panel.isVisible, "⌘\(chars.uppercased()) скрыл панель")
            controller?.hide()
            controller = nil
        }
    }

    /// Esc, когда ничего не открыто, скрывает панель — и с набранным текстом, который остаётся.
    func testEscapeHidesPanelKeepingText() throws {
        let panel = try showPanel()
        let editor = try XCTUnwrap(panel.firstResponder as? NSTextView)
        editor.insertText("ls -la", replacementRange: NSRange(location: 0, length: 0))
        spin()
        key(53, "\u{1b}", to: panel)
        wait { !panel.isVisible }
        XCTAssertFalse(panel.isVisible, "Esc скрыл панель")
        XCTAssertEqual(editor.string, "ls -la", "набранное осталось")
    }

    /// Esc и ⌘W закрывают верхний слой по одному: режим буфера, потом — панель.
    func testEscapeAndCommandWStepBackOneLayer() throws {
        for (code, chars, flags) in [(UInt16(53), "\u{1b}", NSEvent.ModifierFlags()), (UInt16(13), "w", .command)] {
            let panel = try showPanel()
            key(21, "4", .command, to: panel) // ⌘4 — режим буфера
            key(code, chars, flags, to: panel)
            spin()
            XCTAssertTrue(panel.isVisible, "первое нажатие закрыло только режим буфера")
            key(code, chars, flags, to: panel)
            wait { !panel.isVisible }
            XCTAssertFalse(panel.isVisible, "второе — скрыло панель")
            controller?.hide()
            controller = nil
        }
    }

    /// ⌘W во всплывающем окне (дерево папок) закрывает только его, как Esc.
    func testCommandWClosesPopupOnly() throws {
        let panel = try showPanel()
        key(18, "1", .command, to: panel) // ⌘1
        wait { panel.childWindows?.count == 1 }
        let tree = try XCTUnwrap(panel.childWindows?.first)
        key(13, "w", .command, to: tree)
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "дерево закрылось")
        XCTAssertTrue(panel.isVisible, "панель осталась")
        wait { self.inputHasFocus(panel) }
        XCTAssertTrue(inputHasFocus(panel))
    }

    /// ⌘W в настройках закрывает их, как Esc; панель остаётся.
    func testCommandWClosesSettingsOnly() throws {
        let panel = try showPanel()
        key(43, ",", .command, to: panel)
        wait { panel.childWindows?.count == 1 }
        let sheet = try XCTUnwrap(panel.childWindows?.first)
        key(13, "w", .command, to: sheet)
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "настройки закрылись")
        XCTAssertTrue(panel.isVisible, "панель осталась")
    }

    /// В режиме буфера ⌃L чистит буфер (закреплённые остаются), а не историю команд.
    func testClearInClipboardModeClearsClipboard() throws {
        let panel = try showPanel()
        store.add(Session(command: "echo done", state: .completed))
        let now = Date()
        clipboard.record(Clip(text: "keep", copiedAt: now), days: 7)
        clipboard.togglePin(try XCTUnwrap(clipboard.clips.first))
        clipboard.record(Clip(text: "drop", copiedAt: now), days: 7)
        key(21, "4", .command, to: panel) // ⌘4
        key(37, "l", .control, to: panel) // ⌃L
        XCTAssertEqual(clipboard.clips.map(\.text), ["keep"], "незакреплённое убрано, закреплённое осталось")
        XCTAssertEqual(store.sessions.count, 1, "история команд не тронута")
    }

    // MARK: - Настройки отдельным окном

    /// ⌘, открывает настройки своим окном: высота панели не меняется. Esc закрывает, фокус — в поле.
    func testSettingsOpenInOwnWindow() throws {
        let panel = try showPanel()
        let height = panel.frame.height
        key(43, ",", .command, to: panel) // ⌘,
        wait { panel.childWindows?.count == 1 }
        let sheet = try XCTUnwrap(panel.childWindows?.first, "настройки — отдельное окно")
        spin(0.5)
        XCTAssertEqual(panel.frame.height, height, accuracy: 1, "панель не растянулась под настройки")
        XCTAssertGreaterThan(sheet.frame.height, 300)
        key(53, "\u{1b}", to: sheet)
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "Esc закрыл настройки")
        XCTAssertTrue(panel.isVisible, "панель осталась")
        wait { self.inputHasFocus(panel) }
        XCTAssertTrue(inputHasFocus(panel), "фокус снова в поле")
    }

    /// Пока записывается хоткей, Esc и ⌘W достаются записи, а не закрывают настройки и панель.
    func testKeysWhileRecordingHotkeyStayInSettings() throws {
        let panel = try showPanel()
        key(43, ",", .command, to: panel)
        wait { panel.childWindows?.count == 1 }
        let sheet = try XCTUnwrap(panel.childWindows?.first)
        // как запись в HotKeyCapsField: забирает нажатия себе
        HotKeyCapsField.isRecording = true
        var recorded: [UInt16] = []
        let recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            recorded.append(event.keyCode)
            return nil
        }
        defer {
            recorder.map(NSEvent.removeMonitor)
            HotKeyCapsField.isRecording = false
        }
        key(13, "w", .command, to: sheet) // ⌘W
        key(53, "\u{1b}", to: sheet) // Esc
        XCTAssertEqual(recorded, [13, 53], "нажатия получила запись")
        XCTAssertEqual(panel.childWindows?.count, 1, "настройки открыты")
        XCTAssertTrue(panel.isVisible, "панель не скрылась")
    }

    // MARK: - Порядок избранного

    /// ⌘↓ в «Избранном» сдвигает выбранную папку ниже; ⌘↑ на верху раздела ничего не делает.
    func testCommandArrowsReorderFavorites() throws {
        let panel = try showPanel()
        key(14, "e", .command, to: panel) // ⌘E
        wait { panel.childWindows?.count == 1 }
        let favorites = try XCTUnwrap(panel.childWindows?.first)
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        key(126, up, [.command, .function, .numericPad], to: favorites) // ⌘↑ на верху — стоп
        XCTAssertEqual(settings.favoriteDirectories, ["/usr", "/tmp"])
        key(125, down, [.command, .function, .numericPad], to: favorites) // ⌘↓
        wait { self.settings.favoriteDirectories.first == "/tmp" }
        XCTAssertEqual(settings.favoriteDirectories, ["/tmp", "/usr"])
        key(125, down, [.command, .function, .numericPad], to: favorites) // уже внизу — стоп
        XCTAssertEqual(settings.favoriteDirectories, ["/tmp", "/usr"])
    }

    // MARK: - Фильтр набором

    /// В «Избранном» буквы фильтруют, Enter открывает найденное; Esc сначала очищает фильтр, затем закрывает.
    func testTypingFiltersFavorites() throws {
        let panel = try showPanel()
        key(14, "e", .command, to: panel) // ⌘E
        wait { panel.childWindows?.count == 1 }
        let favorites = try XCTUnwrap(panel.childWindows?.first)
        key(17, "t", to: favorites) // «t» — /tmp
        key(36, "\r", to: favorites) // Enter
        wait { self.settings.currentDirectory == "/tmp" }
        XCTAssertEqual(settings.currentDirectory, "/tmp", "Enter открыл найденную папку, а не первую в списке")

    }

    func testEscapeClearsFavoritesFilterFirst() throws {
        let panel = try showPanel()
        key(14, "e", .command, to: panel)
        wait { panel.childWindows?.count == 1 }
        let favorites = try XCTUnwrap(panel.childWindows?.first)
        key(32, "u", to: favorites)
        key(53, "\u{1b}", to: favorites) // Esc — очистить фильтр
        XCTAssertEqual(panel.childWindows?.count, 1, "первый Esc только очистил фильтр")
        key(53, "\u{1b}", to: favorites) // Esc — закрыть
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "второй Esc закрыл избранное")
    }

    /// Delete (Backspace) стирает фильтр посимвольно: «ux» → «u» — снова находится /usr.
    func testDeleteErasesFilterCharacter() throws {
        let panel = try showPanel()
        key(14, "e", .command, to: panel) // ⌘E
        wait { panel.childWindows?.count == 1 }
        let favorites = try XCTUnwrap(panel.childWindows?.first)
        key(32, "u", to: favorites)
        key(7, "x", to: favorites) // «ux» — ничего не найдено
        key(51, "\u{7F}", to: favorites) // Delete
        key(36, "\r", to: favorites) // Enter — /usr
        wait { self.settings.currentDirectory == "/usr" }
        XCTAssertEqual(settings.currentDirectory, "/usr", "Delete стёр «x», и Enter открыл /usr")
    }

    /// ⌘1 в режиме буфера — просмотр картинки, а не дерево папок.
    func testCommandOneInClipboardDoesNotOpenTree() throws {
        let panel = try showPanel()
        key(21, "4", .command, to: panel) // ⌘4
        key(18, "1", .command, to: panel) // ⌘1: картинки не выбрано — звук, дерево не открывается
        spin()
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "дерево папок не открылось")
        key(21, "4", .command, to: panel) // обратно к командам
        key(18, "1", .command, to: panel)
        wait { panel.childWindows?.count == 1 }
        XCTAssertEqual(panel.childWindows?.count, 1, "вне буфера ⌘1 — снова дерево папок")
    }

    /// ⌘S в списке буфера закрепляет выбранный фрагмент, повторно — открепляет.
    func testCommandSPinsSelectedClip() throws {
        let panel = try showPanel()
        clipboard.record(Clip(text: "first", copiedAt: Date().addingTimeInterval(-60)), days: 7)
        clipboard.record(Clip(text: "second", copiedAt: Date()), days: 7)
        key(21, "4", .command, to: panel) // ⌘4
        key(1, "s", .command, to: panel)  // ⌘S
        XCTAssertEqual(clipboard.clips.first { $0.text == "second" }?.isPinned, true)
        key(1, "s", .command, to: panel)
        XCTAssertEqual(clipboard.clips.first { $0.text == "second" }?.isPinned, false, "выбор пошёл за строкой")
    }

    /// Просмотр картинки — окно над панелью: ⌘W закрывает только его; ⌘⌫ удаляет картинку и закрывает.
    func testPreviewKeys() throws {
        let panel = try showPanel()
        let image = try XCTUnwrap(clipboard.recordImage(png: ClipboardImageTests.png(), width: 240, height: 120,
                                                        app: nil, bundleID: nil, days: 7))
        key(21, "4", .command, to: panel) // ⌘4
        key(18, "1", .command, to: panel) // ⌘1 — просмотр
        wait { panel.childWindows?.count == 1 }
        let preview = try XCTUnwrap(panel.childWindows?.first as? ClipPreviewPanel)
        // картинка во всё окно, сверху шапка
        XCTAssertEqual(preview.frame.width, 240)
        XCTAssertEqual(preview.frame.height, 120 + ClipPreviewWindow.headerHeight)
        // за шапку тянут везде, и по подписи с подсказками, кроме кнопок
        let content = try XCTUnwrap(preview.contentView)
        for x: CGFloat in [20, 120] {
            let hit = content.hitTest(NSPoint(x: x, y: content.bounds.height - 15))
            XCTAssertTrue(hit is WindowDragArea.DragView, "x \(x): \(String(describing: hit))")
        }
        key(13, "w", .command, to: preview) // ⌘W
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "⌘W закрыл просмотр")
        XCTAssertTrue(panel.isVisible, "панель осталась")
        key(18, "1", .command, to: panel) // всё ещё буфер: ⌘1 — снова просмотр, не дерево
        wait { panel.childWindows?.count == 1 }
        let again = try XCTUnwrap(panel.childWindows?.first)
        key(51, "\u{7F}", .command, to: again) // ⌘⌫
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertFalse(clipboard.clips.contains { $0.id == image.id }, "картинка удалена")
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "просмотр закрылся вместе с ней")
    }

    /// ⌘S в просмотре закрепляет окно поверх остальных: оно остаётся, когда Hatch скрыт, и видно
    /// на всех рабочих столах; фрагмент в буфере при этом не закрепляется. ⌘Q закрывает окно.
    func testPinnedPreviewStaysWhenHatchHides() throws {
        let panel = try showPanel()
        _ = try XCTUnwrap(clipboard.recordImage(png: ClipboardImageTests.png(), width: 240, height: 120,
                                                app: nil, bundleID: nil, days: 7))
        key(21, "4", .command, to: panel) // ⌘4
        key(18, "1", .command, to: panel) // ⌘1
        wait { panel.childWindows?.count == 1 }
        let preview = try XCTUnwrap(panel.childWindows?.first as? ClipPreviewPanel)
        key(1, "s", .command, to: preview) // ⌘S
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "закреплённое — не дочернее окно панели")
        XCTAssertTrue(preview.isVisible)
        XCTAssertTrue(preview.collectionBehavior.contains(.canJoinAllSpaces), "на всех рабочих столах")
        XCTAssertEqual(clipboard.clips.first?.isPinned, false, "в буфере не закрепилось")

        controller?.hide()
        spin()
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(preview.isVisible, "Hatch скрыт — закреплённое окно на месте")

        key(12, "q", .command, to: preview) // ⌘Q
        wait { !preview.isVisible }
        XCTAssertFalse(preview.isVisible, "⌘Q закрыл закреплённое окно")
    }

    /// Клик мимо (в том числе по самой панели, по списку) закрывает просмотр.
    func testPreviewClosesOnClickInPanel() throws {
        let panel = try showPanel()
        _ = try XCTUnwrap(clipboard.recordImage(png: ClipboardImageTests.png(), width: 240, height: 120,
                                                app: nil, bundleID: nil, days: 7))
        key(21, "4", .command, to: panel) // ⌘4
        key(18, "1", .command, to: panel) // ⌘1
        wait { panel.childWindows?.count == 1 }
        let point = NSPoint(x: panel.frame.width / 2, y: 20) // низ панели — список
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: panel.windowNumber, context: nil,
                                                         eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
        wait { (panel.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "клик по панели закрыл просмотр")
        XCTAssertTrue(panel.isVisible)
    }

    /// ⌘4 — режим буфера: курсор остаётся в поле, можно сразу набирать запрос. Ломалось при включённой
    /// в macOS навигации с клавиатуры: список с прокруткой забирал клавиатуру у поля (нужно 2+ фрагмента
    /// и активное приложение).
    func testClipboardModeKeepsInputFocus() throws {
        let panel = try showPanel()
        clipboard.record(Clip(text: "first", copiedAt: Date().addingTimeInterval(-5)), days: 7)
        _ = clipboard.recordImage(png: ClipboardImageTests.png(), width: 240, height: 120, app: nil, bundleID: nil, days: 7)
        NSApp.activate(ignoringOtherApps: true)
        addTeardownBlock { NSApp.deactivate() } // остальные тесты — как раньше, в неактивном приложении
        panel.makeKey()
        spin(0.5)
        key(21, "4", .command, to: panel) // ⌘4
        wait { self.inputHasFocus(panel) }
        XCTAssertTrue(inputHasFocus(panel), "в буфере фокус у \(String(describing: panel.firstResponder))")
        key(21, "4", .command, to: panel) // обратно к командам
        wait { self.inputHasFocus(panel) }
        XCTAssertTrue(inputHasFocus(panel), "после выхода фокус у \(String(describing: panel.firstResponder))")
    }

    /// Просмотр картинки: ⌘A выделяет весь текст на ней (Live Text), Esc сначала снимает выделение,
    /// ⌘V — выделенное в поле ввода. Распознавание — настоящее, на этом Mac.
    func testPreviewSelectsTextAndInsertsIt() throws {
        let panel = try showPanel()
        _ = clipboard.recordImage(png: ClipboardImageTests.png("HATCH 2048", width: 420, height: 120), width: 420, height: 120,
                                  app: nil, bundleID: nil, days: 7)
        key(21, "4", .command, to: panel) // ⌘4
        key(18, "1", .command, to: panel) // ⌘1 — просмотр
        wait { panel.childWindows?.count == 1 }
        let preview = try XCTUnwrap(panel.childWindows?.first)
        let overlay = try XCTUnwrap(Self.find(ImageAnalysisOverlayView.self, in: preview.contentView!))
        let deadline = Date().addingTimeInterval(8)
        while overlay.text.isEmpty, Date() < deadline { spin(0.1) } // текст распознаётся не сразу
        XCTAssertTrue(overlay.text.contains("HATCH"), "распознано: \(overlay.text)")

        key(0, "a", .command, to: preview) // ⌘A
        XCTAssertTrue(overlay.selectedText.contains("HATCH"), "выделено: \(overlay.selectedText)")
        key(53, "\u{1b}", [], to: preview) // Esc — снять выделение, просмотр остаётся
        XCTAssertFalse(overlay.hasActiveTextSelection)
        XCTAssertEqual(panel.childWindows?.count, 1, "первый Esc не закрыл просмотр")

        key(0, "a", .command, to: preview)
        key(9, "v", .command, to: preview) // ⌘V — в поле ввода
        wait { (panel.childWindows?.count ?? 0) == 0 }
        let field = try XCTUnwrap(textField(in: panel.contentView!))
        wait { field.stringValue.contains("HATCH") }
        XCTAssertTrue(field.stringValue.contains("HATCH 2048"), "в поле: \(field.stringValue)")
        XCTAssertEqual(panel.childWindows?.count ?? 0, 0, "просмотр закрылся")
    }

    /// Закреплённое окно при скрытом Hatch: ⌘V показывает Hatch и вставляет выделенное в поле.
    func testPinnedPreviewInsertShowsHatch() throws {
        let panel = try showPanel()
        _ = clipboard.recordImage(png: ClipboardImageTests.png("HATCH 2048", width: 420, height: 120), width: 420, height: 120,
                                  app: nil, bundleID: nil, days: 7)
        key(21, "4", .command, to: panel) // ⌘4
        key(18, "1", .command, to: panel) // ⌘1
        wait { panel.childWindows?.count == 1 }
        let preview = try XCTUnwrap(panel.childWindows?.first as? ClipPreviewPanel)
        let overlay = try XCTUnwrap(Self.find(ImageAnalysisOverlayView.self, in: preview.contentView!))
        let deadline = Date().addingTimeInterval(8)
        while overlay.text.isEmpty, Date() < deadline { spin(0.1) }
        key(1, "s", .command, to: preview) // ⌘S — закрепить
        controller?.hide()
        spin()
        XCTAssertFalse(panel.isVisible)

        key(0, "a", .command, to: preview) // ⌘A
        key(9, "v", .command, to: preview) // ⌘V
        wait { panel.isVisible }
        XCTAssertTrue(panel.isVisible, "Hatch показался")
        let field = try XCTUnwrap(textField(in: panel.contentView!))
        wait { field.stringValue.contains("HATCH") }
        XCTAssertTrue(field.stringValue.contains("HATCH 2048"), "в поле: \(field.stringValue)")
        XCTAssertTrue(preview.isVisible, "закреплённое окно осталось")
        key(53, "\u{1b}", [], to: preview) // Esc — снять выделение
        key(53, "\u{1b}", [], to: preview) // Esc — закрыть
        wait { !preview.isVisible }
        XCTAssertFalse(preview.isVisible)
    }

    /// Клик по миниатюре скриншота: снимок открывается окном просмотра, панель Hatch остаётся скрытой.
    func testOpenClipShowsOnlyPreview() throws {
        let panel = try showPanel()
        let image = try XCTUnwrap(clipboard.recordImage(png: ClipboardImageTests.png(), width: 240, height: 120,
                                                        app: "Screenshot", bundleID: nil, days: 7))
        controller?.hide()
        spin()
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        NotificationCenter.default.post(name: .hatchOpenClip, object: image.id, userInfo: ["screen": NSValue(rect: screen)])
        var preview: ClipPreviewPanel? { NSApp.windows.compactMap { $0 as? ClipPreviewPanel }.first { $0.isVisible } }
        wait { preview != nil }
        let window = try XCTUnwrap(preview, "снимок открыт окном просмотра")
        XCTAssertFalse(panel.isVisible, "панель Hatch не показалась")
        XCTAssertNil(window.parent)
        XCTAssertEqual(window.preview?.model.clipID, image.id)
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 1, "по центру экрана")
        key(53, "\u{1b}", [], to: window) // Esc — закрыть
        wait { !window.isVisible }
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(panel.isVisible)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let found = find(type, in: sub) { return found } }
        return nil
    }
}
