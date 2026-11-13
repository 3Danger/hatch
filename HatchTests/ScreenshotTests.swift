import XCTest
import AppKit
@testable import Hatch

/// Скриншоты Hatch: занятость сочетания в macOS, стопка миниатюр и её таймер, снимок — в историю и в буфер.
@MainActor
final class ScreenshotTests: XCTestCase {
    private func binding(_ spec: String) throws -> KeyBinding { try XCTUnwrap(KeyBindingParser.parse(spec)) }

    func testDefaultSystemShortcutTakesCommandShift4() throws {
        // записи нет — у macOS сочетание по умолчанию и включено
        XCTAssertTrue(SystemScreenshotShortcuts.isTaken(try binding("cmd-shift-4"), symbolicHotKeys: nil))
        XCTAssertTrue(SystemScreenshotShortcuts.isTaken(try binding("cmd-shift-5"), symbolicHotKeys: nil))
        XCTAssertFalse(SystemScreenshotShortcuts.isTaken(try binding("alt-shift-4"), symbolicHotKeys: nil))
    }

    func testDisabledOrRemappedSystemShortcut() throws {
        let off: [String: Any] = ["30": ["enabled": false]]
        XCTAssertFalse(SystemScreenshotShortcuts.isTaken(try binding("cmd-shift-4"), symbolicHotKeys: off), "выключили в настройках")
        // ⇧⌘4 переназначили на ⇧⌘7: занято уже оно
        let moved: [String: Any] = ["30": ["enabled": true, "value": ["parameters": [55, 26, 1_179_648], "type": "standard"]]]
        XCTAssertFalse(SystemScreenshotShortcuts.isTaken(try binding("cmd-shift-4"), symbolicHotKeys: moved))
        XCTAssertTrue(SystemScreenshotShortcuts.isTaken(try binding("cmd-shift-7"), symbolicHotKeys: moved))
    }

    func testDisplay() {
        XCTAssertEqual(SystemScreenshotShortcuts.display("cmd-shift-4"), "⇧⌘4")
        XCTAssertEqual(SystemScreenshotShortcuts.display("ctrl-alt-space"), "⌃⌥Space")
    }

    func testThumbnailStackNewestAtBottom() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let frames = ScreenshotThumbnails.frames(sizes: [CGSize(width: 200, height: 100), CGSize(width: 150, height: 120)],
                                                 in: visible)
        XCTAssertEqual(frames[1], NSRect(x: 1000 - 16 - 150, y: 16, width: 150, height: 120), "новая — внизу справа")
        XCTAssertEqual(frames[0], NSRect(x: 1000 - 16 - 200, y: 16 + 120 + 10, width: 200, height: 100), "прежняя — над ней")
    }

    func testThumbnailSize() {
        XCTAssertEqual(ScreenshotThumbnails.size(for: CGSize(width: 1440, height: 900)), CGSize(width: 200, height: 125))
        XCTAssertEqual(ScreenshotThumbnails.size(for: CGSize(width: 100, height: 1000)), CGSize(width: 90, height: 150))
    }

    /// Четвёртая вытесняет самую старую; время стоит, пока курсор над стопкой; вышло — миниатюры уходят.
    func testThumbnailTimers() {
        let thumbnails = ScreenshotThumbnails(seconds: { 10 })
        let image = NSImage(size: NSSize(width: 40, height: 20))
        for _ in 0..<4 { thumbnails.add(image: image, png: Data(), clipID: nil, date: Date()) }
        XCTAssertEqual(thumbnails.items.count, ScreenshotThumbnails.maxVisible)
        thumbnails.tick(5)
        XCTAssertEqual(thumbnails.items[0].model.progress, 0.5, accuracy: 0.001)
        thumbnails.items[0].onHover(true)
        thumbnails.tick(20)
        XCTAssertEqual(thumbnails.items.count, 3, "курсор над стопкой — время стоит")
        thumbnails.items[0].onHover(false)
        thumbnails.tick(6)
        XCTAssertTrue(thumbnails.items.isEmpty, "время вышло")
    }

    /// «✓ В буфере» видна первые секунды и гаснет.
    func testBadgeShowsThenHides() {
        let thumbnails = ScreenshotThumbnails(seconds: { 10 })
        thumbnails.add(image: NSImage(size: NSSize(width: 40, height: 20)), png: Data(), clipID: nil, date: Date(), badge: "In clipboard")
        let model = thumbnails.items[0].model
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(model.badgeVisible)
        RunLoop.main.run(until: Date().addingTimeInterval(ScreenshotThumbnail.badgeDuration))
        XCTAssertFalse(model.badgeVisible)
        thumbnails.items.forEach { thumbnails.remove($0, slide: false) }
    }

    /// Готовый снимок — в историю Hatch (подпись «Screenshot»), в системный буфер и миниатюрой.
    func testCaptureGoesToHistoryPasteboardAndThumbnail() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ScreenshotTests.\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: defaults)
        settings.clipboardRecognizeText = false
        let history = ClipboardHistory(fileURL: nil, imagesDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("shots-\(UUID().uuidString)"))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("hatch-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let thumbnails = ScreenshotThumbnails(seconds: { 10 })
        let service = ScreenshotService(history: history, settings: settings, pasteboard: pasteboard, thumbnails: thumbnails)

        let clip = try XCTUnwrap(service.add(png: ClipboardImageTests.png(), at: Date()))
        XCTAssertEqual(history.clips.first?.id, clip.id)
        XCTAssertEqual(clip.app, "Screenshot")
        XCTAssertEqual(clip.image?.width, 240)
        XCTAssertNotNil(pasteboard.data(forType: .png), "снимок в буфере обмена")
        XCTAssertEqual(thumbnails.items.first?.clipID, clip.id)
        thumbnails.items.forEach { thumbnails.remove($0, slide: false) }
    }
}
