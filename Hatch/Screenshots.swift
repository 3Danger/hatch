import SwiftUI
import AppKit
import ImageIO

extension Notification.Name {
    /// Открыть картинку из буфера окном просмотра, без панели (клик по миниатюре снимка):
    /// `object` — UUID фрагмента, `userInfo["screen"]` — видимая часть экрана (NSValue с NSRect).
    static let hatchOpenClip = Notification.Name("hatch.openClip")
}

// MARK: - Системные сочетания снимков экрана

/// Сочетания снимков экрана самой macOS (Клавиатура → Сочетания клавиш → Снимки экрана). Пока такое
/// включено, система перехватывает его раньше любого приложения — Hatch подсказывает, где выключить.
enum SystemScreenshotShortcuts {
    struct Shortcut: Equatable {
        let keyCode: Int
        /// Модификаторы как в NSEvent (так их хранит macOS).
        let modifiers: Int
    }

    private static let shift = 0x20000, control = 0x40000, option = 0x80000, command = 0x100000

    /// Номер в com.apple.symbolichotkeys → сочетание по умолчанию.
    static let defaults: [Int: Shortcut] = [
        28: Shortcut(keyCode: 20, modifiers: shift | command),           // ⇧⌘3 — экран в файл
        29: Shortcut(keyCode: 20, modifiers: control | shift | command), // ⌃⇧⌘3 — экран в буфер
        30: Shortcut(keyCode: 21, modifiers: shift | command),           // ⇧⌘4 — область в файл
        31: Shortcut(keyCode: 21, modifiers: control | shift | command), // ⌃⇧⌘4 — область в буфер
        184: Shortcut(keyCode: 23, modifiers: shift | command),          // ⇧⌘5 — панель снимков
    ]

    /// Сочетание Hatch (Carbon) — в виде macOS.
    static func shortcut(for binding: KeyBinding) -> Shortcut {
        var modifiers = 0
        if binding.modifiers & CarbonModifiers.shift != 0 { modifiers |= shift }
        if binding.modifiers & CarbonModifiers.control != 0 { modifiers |= control }
        if binding.modifiers & CarbonModifiers.option != 0 { modifiers |= option }
        if binding.modifiers & CarbonModifiers.command != 0 { modifiers |= command }
        return Shortcut(keyCode: Int(binding.keyCode), modifiers: modifiers)
    }

    /// Занято ли сочетание включённым снимком экрана macOS. `symbolicHotKeys` — содержимое
    /// AppleSymbolicHotKeys: нет записи — сочетание по умолчанию и включено.
    static func isTaken(_ binding: KeyBinding, symbolicHotKeys: [String: Any]?) -> Bool {
        let wanted = shortcut(for: binding)
        for (id, standard) in defaults {
            let entry = symbolicHotKeys?[String(id)] as? [String: Any]
            let enabled = (entry?["enabled"] as? NSNumber)?.boolValue ?? true
            guard enabled else { continue }
            var current = standard
            if let parameters = (entry?["value"] as? [String: Any])?["parameters"] as? [NSNumber], parameters.count >= 3 {
                current = Shortcut(keyCode: parameters[1].intValue, modifiers: parameters[2].intValue & (shift | control | option | command))
            }
            if current == wanted { return true }
        }
        return false
    }

    static func isTaken(_ spec: String) -> Bool {
        guard let binding = KeyBindingParser.parse(spec) else { return false }
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return isTaken(binding, symbolicHotKeys: hotKeys)
    }

    /// «cmd-shift-4» → «⇧⌘4», как в меню macOS.
    static func display(_ spec: String) -> String {
        let parts = spec.lowercased().split(separator: "-").map(String.init)
        let symbols: [(String, String)] = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")]
        let modifiers = symbols.filter { parts.contains($0.0) }.map(\.1).joined()
        let key = parts.last { name in !symbols.contains { $0.0 == name } } ?? ""
        return modifiers + (key.count == 1 ? key.uppercased() : key.capitalized)
    }

    /// Настройки клавиатуры: там «Сочетания клавиш…» → «Снимки экрана».
    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Снимок

/// Снимок области экрана по сочетанию: выделяет системное перекрестие (`screencapture -i`: Пробел —
/// окно, Esc — отмена), снимок — в историю буфера Hatch и в системный буфер, справа внизу миниатюра.
@MainActor
final class ScreenshotService {
    private let history: ClipboardHistory
    private let settings: SettingsStore
    private let pasteboard: NSPasteboard
    let thumbnails: ScreenshotThumbnails
    private var capturing = false

    init(history: ClipboardHistory, settings: SettingsStore, pasteboard: NSPasteboard = .general,
         thumbnails: ScreenshotThumbnails) {
        self.history = history
        self.settings = settings
        self.pasteboard = pasteboard
        self.thumbnails = thumbnails
    }

    func capture() {
        guard !capturing else { return }
        capturing = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hatch-shot-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", url.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async { [weak self] in self?.finish(url) }
        }
        do {
            try process.run()
        } catch {
            capturing = false
        }
    }

    private func finish(_ url: URL) {
        capturing = false
        defer { try? FileManager.default.removeItem(at: url) }
        // Esc — файла нет
        guard let png = try? Data(contentsOf: url), !png.isEmpty else { return }
        add(png: png)
    }

    /// Снимок готов: в историю Hatch, в системный буфер (⌘V куда угодно) и миниатюрой справа внизу.
    @discardableResult
    func add(png: Data, at date: Date = Date()) -> Clip? {
        guard let size = Self.pixelSize(png), let image = NSImage(data: png) else { return nil }
        var clip: Clip?
        if settings.clipboardEnabled {
            clip = history.recordImage(png: png, width: size.width, height: size.height,
                                       app: L.t("screenshot_source", settings.languageCode), bundleID: nil,
                                       at: date, days: settings.clipboardDays)
            if let clip, settings.clipboardRecognizeText, clip.image?.text == nil, let url = history.imageURL(clip) {
                let history = history
                TextRecognizer.shared.recognize(url) { text in history.setRecognizedText(text, for: clip.id) }
            }
        }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = image.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        // та же картинка из буфера в историю второй раз не попадёт (сверяется по содержимому)
        pasteboard.setString("", forType: Clipboard.hatchMarker)
        thumbnails.add(image: image, png: png, clipID: clip?.id, date: date,
                       badge: L.t("screenshot_in_clipboard", settings.languageCode))
        return clip
    }

    static func pixelSize(_ png: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

// MARK: - Миниатюры

/// Миниатюры снимков справа внизу экрана: стопкой, новая снизу, у каждой свой таймер.
/// Курсор над любой — все стоят. Клик — снимок в буфере Hatch; смахнуть — убрать; перетащить — файлом.
@MainActor
final class ScreenshotThumbnails {
    static let maxVisible = 3
    static let maxSize = CGSize(width: 200, height: 150)
    static let minWidth: CGFloat = 90
    static let gap: CGFloat = 10
    static let margin: CGFloat = 16

    /// Сколько секунд висит миниатюра.
    var seconds: () -> TimeInterval
    /// Клик по миниатюре: открыть снимок окном просмотра на экране миниатюры.
    var onOpen: (UUID, NSRect?) -> Void = { _, _ in }
    /// Самая старая первой (вверху стопки).
    private(set) var items: [ScreenshotThumbnail] = []
    private var timer: Timer?
    private var lastTick: Date?
    private var hovered = 0

    init(seconds: @escaping () -> TimeInterval) {
        self.seconds = seconds
    }

    var isPaused: Bool { hovered > 0 }

    /// `badge` — плашка «✓ В буфере» в углу на первые секунды (nil — без неё).
    func add(image: NSImage, png: Data, clipID: UUID?, date: Date, badge: String? = nil) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let item = ScreenshotThumbnail(image: image, png: png, clipID: clipID, date: date, total: seconds(),
                                       size: Self.size(for: image.size), badge: badge)
        item.onHover = { [weak self] inside in self?.hovered += inside ? 1 : -1 }
        item.onClick = { [weak self, weak item] in
            guard let self, let item else { return }
            if let id = item.clipID { self.onOpen(id, item.screenFrame) }
            self.remove(item, slide: false)
        }
        item.onDismiss = { [weak self, weak item] in
            guard let self, let item else { return }
            self.remove(item, slide: true)
        }
        items.append(item)
        // четвёртая вытесняет самую старую — в истории остаются все
        while items.count > Self.maxVisible { remove(items[0], slide: true) }
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        item.show(at: Self.frames(sizes: items.map(\.size), in: visible).last ?? .zero, slideFrom: visible.maxX)
        layout(in: visible)
        startTimer()
    }

    /// Убрать: смахнули или закончилось время — уезжает вправо, по клику — гаснет.
    func remove(_ item: ScreenshotThumbnail, slide: Bool) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        if item.isHovered { hovered = max(0, hovered - 1) }
        item.close(slide: slide)
        if let screen = item.screenFrame { layout(in: screen) }
        if items.isEmpty { timer?.invalidate(); timer = nil; lastTick = nil; hovered = 0 }
    }

    /// Рамки снизу вверх: последняя (новая) у нижнего края, прежние над ней.
    static func frames(sizes: [CGSize], in visible: NSRect) -> [NSRect] {
        var y = visible.minY + margin
        var frames: [NSRect] = []
        for size in sizes.reversed() {
            frames.append(NSRect(x: visible.maxX - margin - size.width, y: y, width: size.width, height: size.height))
            y += size.height + gap
        }
        return frames.reversed()
    }

    /// Размер миниатюры: картинка, вписанная в 200 × 150, не уже `minWidth`.
    static func size(for image: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return maxSize }
        let scale = min(maxSize.width / image.width, maxSize.height / image.height)
        let width = max(minWidth, (image.width * scale).rounded())
        return CGSize(width: width, height: min(maxSize.height, (image.height * scale).rounded()))
    }

    /// Время идёт, если курсор не над стопкой. `dt` — сколько прошло.
    func tick(_ dt: TimeInterval) {
        guard !isPaused else { return }
        for item in items {
            item.remaining -= dt
            item.model.progress = max(0, item.remaining / item.total)
        }
        items.filter { $0.remaining <= 0 }.forEach { remove($0, slide: true) }
    }

    private func layout(in visible: NSRect) {
        let frames = Self.frames(sizes: items.map(\.size), in: visible)
        for (item, frame) in zip(items, frames) { item.move(to: frame) }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                self.tick(now.timeIntervalSince(self.lastTick ?? now))
                self.lastTick = now
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// Одна миниатюра: своё окно поверх всех, картинка и полоска таймера.
@MainActor
final class ScreenshotThumbnail {
    @MainActor @Observable
    final class Model {
        var progress: Double = 1
        var hovered = false
        /// Плашка «✓ В буфере» видна (первые `badgeDuration` секунд).
        var badgeVisible = false
    }

    /// Сколько секунд видна плашка «✓ В буфере».
    static let badgeDuration: TimeInterval = 2

    let image: NSImage
    let png: Data
    let clipID: UUID?
    let date: Date
    let total: TimeInterval
    var remaining: TimeInterval
    let size: CGSize
    let model = Model()
    let window: NSPanel
    var onHover: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    var onDismiss: () -> Void = {}
    private(set) var isHovered = false
    private(set) var screenFrame: NSRect?

    init(image: NSImage, png: Data, clipID: UUID?, date: Date, total: TimeInterval, size: CGSize, badge: String? = nil) {
        self.image = image
        self.png = png
        self.clipID = clipID
        self.date = date
        self.total = total
        self.remaining = total
        self.size = size
        window = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size))
        let hosting = NSHostingView(rootView: ScreenshotThumbnailContent(image: image, model: model, badge: badge))
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width, .height]
        view.addSubview(hosting)
        view.owner = self
        window.contentView = view
    }

    func show(at frame: NSRect, slideFrom right: CGFloat) {
        screenFrame = NSScreen.screens.first { $0.visibleFrame.intersects(frame) }?.visibleFrame
        window.setFrame(NSRect(x: right + 10, y: frame.minY, width: frame.width, height: frame.height), display: false)
        window.orderFrontRegardless()
        move(to: frame)
        // плашка — когда миниатюра доехала, и гаснет через пару секунд
        let model = model
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.badgeVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Self.badgeDuration) { model.badgeVisible = false }
    }

    func move(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            window.animator().setFrame(frame, display: true)
        }
    }

    func close(slide: Bool) {
        let window = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            if slide {
                var frame = window.frame
                frame.origin.x = (screenFrame?.maxX ?? frame.maxX) + 10
                window.animator().setFrame(frame, display: true)
            }
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }

    fileprivate func setHovered(_ inside: Bool) {
        guard inside != isHovered else { return }
        isHovered = inside
        model.hovered = inside
        onHover(inside)
    }

    /// Файл для перетаскивания: «Снимок экрана 2026-11-13 в 11.20.05.png» во временной папке.
    fileprivate func dragFile() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'в' HH.mm.ss"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Hatch Screenshots", isDirectory: true)
        let url = folder.appendingPathComponent("Снимок экрана \(formatter.string(from: date)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { try png.write(to: url) }
            return url
        } catch {
            return nil
        }
    }
}

/// Мышь у миниатюры: курсор над ней, клик, перетаскивание файлом, смахивание двумя пальцами.
private final class ThumbnailView: NSView, NSDraggingSource {
    weak var owner: ScreenshotThumbnail?
    private var downAt: NSPoint?
    private var dragging = false
    private var swipe: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { owner?.setHovered(true) }
    override func mouseExited(with event: NSEvent) { if !dragging { owner?.setHovered(false) } }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt, !dragging, let owner else { return }
        let point = event.locationInWindow
        guard hypot(point.x - downAt.x, point.y - downAt.y) > 4, let url = owner.dragFile() else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: owner.image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, !dragging else { return }
        owner?.onClick()
    }

    /// Два пальца вправо — убрать (направление — как у пальцев, при любой настройке прокрутки).
    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        if event.phase == .began { swipe = 0 }
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        swipe += fingers
        if swipe > 40 {
            swipe = -.infinity // до конца жеста — больше не срабатывать
            owner?.onDismiss()
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        downAt = nil
        // положили куда-то — миниатюра своё отработала
        if operation != [] { owner?.onDismiss() } else { owner?.setHovered(false) }
    }
}

/// Миниатюра: картинка и тонкая полоска таймера по нижнему краю.
private struct ScreenshotThumbnailContent: View {
    let image: NSImage
    let model: ScreenshotThumbnail.Model
    var badge: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Tactile.clip.opacity(0.9))
                        .frame(width: geo.size.width * model.progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .overlay(alignment: .topLeading) {
                if let badge, model.badgeVisible {
                    // как тост панели («Скопировано: …»): тёмный, со своей тенью; фиолетовая — только галочка
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Tactile.clip)
                        Text(badge).font(.system(size: 11))
                    }
                    .foregroundStyle(Tactile.keyText)
                    .padding(.leading, 7)
                    .padding(.trailing, 9)
                    .frame(height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .circular).fill(Tactile.toast)
                            .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .circular).strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
                    .padding(7)
                    .transition(.opacity.combined(with: .offset(y: -3)))
                }
            }
            .animation(.easeOut(duration: 0.4), value: model.badgeVisible)
            .clipShape(shape)
            .overlay(shape.strokeBorder(model.hovered ? Tactile.clip.opacity(0.7) : Color.white.opacity(0.18)))
    }
}
