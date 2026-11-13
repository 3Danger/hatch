import XCTest
import AppKit
@testable import Hatch

/// Картинки в буфере: файлы, повторы, лимиты, поиск по распознанному тексту, текст важнее картинки.
/// Свой буфер обмена и своя папка — системные не трогаем.
final class ClipboardImageTests: XCTestCase {
    private var folder: URL!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("clip-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("hatch-image-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func history() -> ClipboardHistory {
        ClipboardHistory(fileURL: folder.appendingPathComponent("clipboard.json"))
    }

    /// PNG с надписью: белый фон, чёрный крупный текст.
    static func png(_ text: String = "", width: Int = 240, height: Int = 120, shade: CGFloat = 1) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: shade, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        (text as NSString).draw(at: NSPoint(x: 20, y: CGFloat(height) / 2 - 24),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testImageSavedPrivatelyAndRepeatMovesUp() throws {
        let history = history()
        let first = try XCTUnwrap(history.recordImage(png: Self.png(shade: 1), width: 240, height: 120, app: "Терминал", bundleID: nil, days: 7))
        history.record(Clip(text: "ls", copiedAt: Date()), days: 7)
        let url = try XCTUnwrap(history.imageURL(first))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        // та же картинка снова (например, Enter в Hatch) — наверх, без второго файла и с прежним приложением
        history.recordImage(png: Self.png(shade: 1), width: 240, height: 120, app: "Hatch", bundleID: nil, days: 7)
        XCTAssertEqual(history.clips.first?.id, first.id)
        XCTAssertEqual(history.clips.first?.app, "Терминал")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).count, 1)
    }

    /// Удалённая картинка — файл убирается (не сразу: работает «Отменить»).
    func testRemovedImageFileIsCleanedUp() throws {
        let history = history()
        let clip = try XCTUnwrap(history.recordImage(png: Self.png(), width: 240, height: 120, app: nil, bundleID: nil, days: 7))
        let url = try XCTUnwrap(history.imageURL(clip))
        history.remove(clip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "пока можно отменить, файл на месте")
        history.removeUnusedImageFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testImageLimitAndSize() throws {
        let history = history()
        for i in 0..<(ClipboardHistory.imageLimit + 3) {
            history.recordImage(png: Self.png(shade: CGFloat(i) / 100), width: 240, height: 120, app: nil, bundleID: nil, days: 7)
        }
        XCTAssertEqual(history.clips.filter(\.isImage).count, ClipboardHistory.imageLimit)
        let huge = Data(count: ClipboardHistory.maxImageBytes + 1)
        XCTAssertNil(history.recordImage(png: huge, width: 1, height: 1, app: nil, bundleID: nil, days: 7))
    }

    /// Картинки ищутся по распознанному тексту, приложению и словам «скриншот», «картинка».
    func testImageSearch() throws {
        let history = history()
        let clip = try XCTUnwrap(history.recordImage(png: Self.png(), width: 240, height: 120, app: "Telegram", bundleID: nil, days: 7))
        history.setRecognizedText("Build failed\nError: connection refused", for: clip.id)
        history.record(Clip(text: "git status", copiedAt: Date()), days: 7)
        XCTAssertEqual(history.matching("refused").count, 1)
        XCTAssertEqual(history.matching("teleg").count, 1)
        XCTAssertEqual(history.matching("скрин").count, 1)
        XCTAssertEqual(history.matching("git").map(\.text), ["git status"])
        let found = try XCTUnwrap(history.clips.first { $0.isImage })
        XCTAssertEqual(ClipboardHistory.matchedLine(found, "refused"), "Error: connection refused")
        XCTAssertEqual(found.image?.firstLine, "Build failed")
    }

    // MARK: - Слежение за буфером

    private func watcher(_ history: ClipboardHistory, settings: SettingsStore) -> ClipboardWatcher {
        ClipboardWatcher(pasteboard: pasteboard, history: history, settings: settings, frontmost: { nil })
    }

    private func settings() -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "ClipboardImageTests.\(UUID().uuidString)")!)
        store.clipboardRecognizeText = false // распознавание проверяется отдельно
        return store
    }

    /// Только картинка — сохраняется картинкой; картинка с текстом (ячейки таблицы) — текстом.
    func testTextWinsOverImage() {
        let history = history()
        let watch = watcher(history, settings: settings())
        pasteboard.clearContents()
        pasteboard.setData(Self.png(), forType: .png)
        watch.poll()
        XCTAssertEqual(history.clips.first?.isImage, true)
        XCTAssertEqual(history.clips.first?.image?.width, 240)
        pasteboard.clearContents()
        pasteboard.setString("A1\tB1", forType: .string)
        pasteboard.setData(Self.png("table"), forType: .png)
        watch.poll()
        XCTAssertEqual(history.clips.first?.text, "A1\tB1")
        XCTAssertEqual(history.clips.filter(\.isImage).count, 1)
    }

    func testImagesOffOrPasswordNotSaved() {
        let history = history()
        let store = settings()
        let watch = watcher(history, settings: store)
        store.clipboardImages = false
        pasteboard.clearContents()
        pasteboard.setData(Self.png(), forType: .png)
        watch.poll()
        store.clipboardImages = true
        pasteboard.declareTypes([.png, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setData(Self.png("x"), forType: .png)
        watch.poll()
        XCTAssertTrue(history.clips.isEmpty)
    }

    /// Enter в буфере Hatch кладёт картинку обратно — та же картинка, не новая.
    func testCopyBackKeepsSameClip() throws {
        let history = history()
        let watch = watcher(history, settings: settings())
        pasteboard.clearContents()
        pasteboard.setData(Self.png(), forType: .png)
        watch.poll()
        let clip = try XCTUnwrap(history.clips.first)
        XCTAssertTrue(Clipboard.copyImage(at: try XCTUnwrap(history.imageURL(clip)), to: pasteboard))
        watch.poll()
        XCTAssertEqual(history.clips.count, 1)
        XCTAssertNotNil(pasteboard.data(forType: .tiff), "вставится и туда, где ждут TIFF")
    }

    // MARK: - Распознавание

    func testRecognizesTextOnImage() throws {
        let url = folder.appendingPathComponent("ocr.png")
        try Self.png("HATCH 2048 ERROR", width: 640, height: 160).write(to: url)
        let text = TextRecognizer.recognizeNow(url)
        XCTAssertTrue(text.contains("2048"), "распознано: \(text)")
        XCTAssertTrue(text.uppercased().contains("ERROR"), "распознано: \(text)")
    }

    func testShellEscapedPath() {
        XCTAssertEqual(LauncherRootView.shellEscaped("~/Library/Application Support/Hatch/a.png"),
                       "~/Library/Application\\ Support/Hatch/a.png")
    }

    func testSizeOnInterfaceLanguage() {
        XCTAssertEqual(ClipImage.size(412 * 1024, lang: "ru"), "412 КБ")
        XCTAssertEqual(ClipImage.size(2_200_000, lang: "ru"), "2,1 МБ")
        XCTAssertEqual(ClipImage.size(2_200_000, lang: "en"), "2.1 MB")
    }

    // MARK: - Фильтр по типу

    /// Пути к файлам — в «Тексте»; числа у типов считаются по набранному запросу.
    func testKindsAndCounts() throws {
        let history = history()
        history.record(Clip(text: "~/git/hatch/README.md", copiedAt: Date(), isPath: true), days: 7)
        history.record(Clip(text: "kubectl logs", copiedAt: Date()), days: 7)
        let image = try XCTUnwrap(history.recordImage(png: Self.png(), width: 240, height: 120, app: "Telegram", bundleID: nil, days: 7))
        history.togglePin(image)
        XCTAssertEqual(history.matching("", kind: .text).count, 2, "путь — это текст")
        XCTAssertEqual(history.matching("", kind: .images).count, 1)
        XCTAssertEqual(history.matching("", kind: .pinned).map(\.id), [image.id])
        XCTAssertEqual(history.counts(""), [.all: 3, .text: 2, .images: 1, .pinned: 1])
        XCTAssertEqual(history.counts("kube"), [.all: 1, .text: 1, .images: 0, .pinned: 0])
    }

    func testKindCyclesBothWays() {
        XCTAssertEqual(ClipKind.all.next(1), .text)
        XCTAssertEqual(ClipKind.pinned.next(1), .all)
        XCTAssertEqual(ClipKind.all.next(-1), .pinned)
    }
}
