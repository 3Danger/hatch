import XCTest
import AppKit
@testable import Hatch

/// История буфера: без повторов, срок и лимит, пароли не сохраняются. Системный буфер не трогаем:
/// у тестов свой именованный буфер и свой файл.
final class ClipboardHistoryTests: XCTestCase {
    private var file: URL!
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("clips-\(UUID().uuidString).json")
        pasteboard = NSPasteboard(name: NSPasteboard.Name("hatch-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    private func clip(_ text: String, app: String? = "Safari", at date: Date = Date()) -> Clip {
        Clip(text: text, app: app, bundleID: nil, copiedAt: date)
    }

    func testRepeatedCopyMovesUpAndKeepsSource() {
        let history = ClipboardHistory(fileURL: nil)
        history.record(clip("ssh deploy@host", app: "Терминал"), days: 7)
        history.record(clip("https://example.com"), days: 7)
        history.record(clip("ssh deploy@host", app: "Hatch"), days: 7)
        XCTAssertEqual(history.clips.map(\.text), ["ssh deploy@host", "https://example.com"])
        XCTAssertEqual(history.clips.first?.app, "Терминал", "повторное копирование из Hatch не меняет источник")
    }

    func testEmptyAndHugeTextAreSkipped() {
        let history = ClipboardHistory(fileURL: nil)
        history.record(clip("   \n"), days: 7)
        history.record(clip(String(repeating: "x", count: ClipboardHistory.maxLength + 1)), days: 7)
        XCTAssertTrue(history.clips.isEmpty)
    }

    func testLimitAndAge() {
        let history = ClipboardHistory(fileURL: nil)
        let now = Date()
        history.record(clip("old", at: now.addingTimeInterval(-8 * 86_400)), days: 7)
        for i in 0..<(ClipboardHistory.limit + 5) { history.record(clip("item \(i)", at: now), days: 7) }
        XCTAssertEqual(history.clips.count, ClipboardHistory.limit)
        XCTAssertFalse(history.clips.contains { $0.text == "old" })
        XCTAssertEqual(history.clips.first?.text, "item \(ClipboardHistory.limit + 4)")
    }

    func testMatchingIgnoresCase() {
        let history = ClipboardHistory(fileURL: nil)
        history.record(clip("SSH deploy"), days: 7)
        history.record(clip("git status"), days: 7)
        XCTAssertEqual(history.matching("ssh").map(\.text), ["SSH deploy"])
        XCTAssertEqual(history.matching("  ").count, 2)
    }

    func testPersistsPrivately() throws {
        let history = ClipboardHistory(fileURL: file)
        history.record(clip("secret-ish"), days: 7)
        history.flush()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(ClipboardHistory(fileURL: file).clips.map(\.text), ["secret-ish"])
    }

    // MARK: - Слежение за буфером

    private func watcher(_ history: ClipboardHistory, settings: SettingsStore,
                         frontmost: NSRunningApplication? = nil) -> ClipboardWatcher {
        ClipboardWatcher(pasteboard: pasteboard, history: history, settings: settings, frontmost: { frontmost })
    }

    private func settings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "ClipboardHistoryTests.\(UUID().uuidString)")!)
    }

    func testRecordsTextButNotWhatWasThereBefore() {
        pasteboard.clearContents()
        pasteboard.setString("before launch", forType: .string)
        let history = ClipboardHistory(fileURL: nil)
        let watch = watcher(history, settings: settings())
        watch.poll()
        XCTAssertTrue(history.clips.isEmpty, "скопированное до запуска не записывается")
        pasteboard.clearContents()
        pasteboard.setString("git log", forType: .string)
        watch.poll()
        XCTAssertEqual(history.clips.map(\.text), ["git log"])
    }

    /// Менеджеры паролей помечают пароли скрытыми или временными — их не сохраняем.
    func testConcealedAndTransientAreSkipped() {
        let history = ClipboardHistory(fileURL: nil)
        let watch = watcher(history, settings: settings())
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"] {
            pasteboard.declareTypes([.string, NSPasteboard.PasteboardType(marker)], owner: nil)
            pasteboard.setString("hunter2", forType: .string)
            pasteboard.setString("", forType: NSPasteboard.PasteboardType(marker))
            watch.poll()
        }
        XCTAssertTrue(history.clips.isEmpty)
    }

    func testCopyFromHatchIsMarked() {
        let history = ClipboardHistory(fileURL: nil)
        let watch = watcher(history, settings: settings())
        Clipboard.copy("350", to: pasteboard)
        watch.poll()
        XCTAssertEqual(history.clips.first?.app, "Hatch")
        XCTAssertEqual(history.clips.first?.text, "350")
    }

    func testFilesAreSavedAsPaths() {
        let history = ClipboardHistory(fileURL: nil)
        let watch = watcher(history, settings: settings())
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/usr/bin") as NSURL, URL(fileURLWithPath: "/tmp") as NSURL])
        watch.poll()
        XCTAssertEqual(history.clips.first?.text, "/usr/bin\n/tmp")
        XCTAssertEqual(history.clips.first?.isPath, true)
    }

    func testDisabledOrExcludedAppIsNotSaved() {
        let history = ClipboardHistory(fileURL: nil)
        let store = settings()
        let app = NSRunningApplication.current
        let watch = watcher(history, settings: store, frontmost: app)
        store.clipboardEnabled = false
        pasteboard.clearContents()
        pasteboard.setString("off", forType: .string)
        watch.poll()
        store.clipboardEnabled = true
        store.addClipboardExclusion(try! XCTUnwrap(app.bundleIdentifier))
        pasteboard.clearContents()
        pasteboard.setString("excluded", forType: .string)
        watch.poll()
        XCTAssertTrue(history.clips.isEmpty)
    }

    func testDefaultSettings() {
        let store = settings()
        XCTAssertTrue(store.clipboardEnabled)
        XCTAssertEqual(store.clipboardDays, 7)
        XCTAssertTrue(store.clipboardExcludedApps.contains("com.1password.1password"))
    }
}
