import SwiftUI
import AppKit

/// Просмотр картинки из буфера (⌘1) — отдельное окно: шапка с подсказками клавиш, картинка во всё окно.
/// Тянется за шапку, меняет размер за углы (строго в пропорциях картинки), ⌘S закрепляет
/// поверх окон: закреплённое остаётся, когда Hatch скрыт, и видно на всех рабочих столах.
final class ClipPreviewPanel: NSPanel {
    weak var preview: ClipPreviewWindow?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Что показывает одно окно просмотра.
@MainActor @Observable
final class ClipPreviewModel {
    let clipID: UUID
    let image: NSImage
    /// Файл картинки: копировать её и вставлять путь.
    let url: URL
    /// «1440 × 900 · Терминал».
    let caption: String
    var isPinned = false
    /// Короткое уведомление прямо на окне («Текст скопирован»): у закреплённого окна панели может не быть.
    var toast: String?
    let liveText = LiveTextController()

    init(clipID: UUID, image: NSImage, url: URL, caption: String) {
        self.clipID = clipID
        self.image = image
        self.url = url
        self.caption = caption
    }
}

/// Края окна, за которые меняют размер.
struct PreviewEdges: OptionSet, Hashable {
    let rawValue: Int
    static let left = PreviewEdges(rawValue: 1)
    static let right = PreviewEdges(rawValue: 2)
    static let top = PreviewEdges(rawValue: 4)
    static let bottom = PreviewEdges(rawValue: 8)
}

/// Одно окно просмотра: создаёт, ставит, меняет размер, закрепляет.
@MainActor
final class ClipPreviewWindow {
    static let headerHeight: CGFloat = 30
    static let minWidth: CGFloat = 200
    /// Размер при открытии — не больше этого (меньшая картинка — в свой размер).
    static let openSize = CGSize(width: 900, height: 600)
    static let cornerRadius: CGFloat = 12

    let model: ClipPreviewModel
    let panel: ClipPreviewPanel
    /// Ширина к высоте картинки.
    let ratio: CGFloat
    private var toastTask: Task<Void, Never>?

    init(model: ClipPreviewModel, lang: String, onTogglePin: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.model = model
        let size = model.image.size
        ratio = size.width > 0 && size.height > 0 ? size.width / size.height : 16 / 10
        panel = ClipPreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // тень — по форме окна (скруглённой): окно непрозрачно только там, где карточка
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]

        let container = NSView()
        let hosting = NSHostingView(rootView: ClipPreviewContent(
            model: model, lang: lang, onTogglePin: onTogglePin, onClose: onClose,
            onResetSize: { [weak self] in self?.resetSize() }))
        // размер окна задаёт само окно (по картинке), а не SwiftUI
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        let resizer = PreviewResizeView()
        resizer.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.addSubview(resizer)
        panel.contentView = container
        panel.preview = self
        resizer.onResize = { [weak self] start, edges, delta in self?.resize(from: start, edges: edges, delta: delta) }
        resizer.onEnd = { [weak self] in self?.panel.invalidateShadow() }
    }

    /// Размер окна при открытии и по двойному клику на шапке.
    var openingSize: CGSize {
        let fitted = LiveTextImage.fittedSize(model.image.size, in: Self.openSize)
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1600, height: 1000)
        let width = Self.clampedWidth(fitted.width, ratio: ratio, bounds: visible)
        return CGSize(width: width, height: (width / ratio).rounded() + Self.headerHeight)
    }

    /// Показать над `anchor` (рамка списка буфера на экране): по центру, верхние края вровень.
    func show(over anchor: NSRect?, parent: NSWindow?) {
        let size = openingSize
        let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let base = anchor ?? parent?.frame ?? screen
        var origin = NSPoint(x: base.midX - size.width / 2, y: base.maxY - size.height)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if let parent { panel.appearance = parent.effectiveAppearance; parent.addChildWindow(panel, ordered: .above) }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Показать само по себе, без панели (клик по миниатюре скриншота): по центру `visible`.
    func show(centeredIn visible: NSRect) {
        let size = openingSize
        panel.setFrame(NSRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)
        if let launcher = NSApp.windows.first(where: { $0 is LauncherPanel }) { panel.appearance = launcher.effectiveAppearance }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        toastTask?.cancel()
        panel.parent?.removeChildWindow(panel)
        let wasKey = panel.isKeyWindow
        panel.orderOut(nil)
        // клавиатура — обратно панели Hatch, если она на экране
        if wasKey, let launcher = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) { launcher.makeKey() }
    }

    /// Закреплённое — само по себе: не уходит вместе с панелью и есть на всех рабочих столах.
    func setPinned(_ pinned: Bool) {
        model.isPinned = pinned
        if pinned { panel.parent?.removeChildWindow(panel) }
        panel.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
    }

    func showToast(_ text: String) {
        model.toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self else { return }
            if self.model.toast == text { self.model.toast = nil }
        }
    }

    func resetSize() {
        let size = openingSize
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                       display: true, animate: true)
        panel.invalidateShadow()
    }

    private func resize(from start: NSRect, edges: PreviewEdges, delta: CGSize) {
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        panel.setFrame(Self.resized(start, edges: edges, delta: delta, ratio: ratio, header: Self.headerHeight,
                                    bounds: bounds.size), display: true)
    }

    /// Ширина картинки в пределах: не уже `minWidth`, не больше экрана ни по ширине, ни по высоте.
    nonisolated static func clampedWidth(_ width: CGFloat, ratio: CGFloat, bounds: CGSize,
                                         header: CGFloat = headerHeight) -> CGFloat {
        let largest = max(minWidth, min(bounds.width, (bounds.height - header) * ratio))
        return min(max(width, minWidth), largest).rounded()
    }

    /// Новая рамка окна, когда тянут за `edges` на `delta` (в координатах экрана: `height` — вверх).
    /// Картинка остаётся в своих пропорциях: высота окна — по ширине, плюс шапка. Неподвижен
    /// противоположный край (угол); за левый или правый край — ещё и верхний.
    nonisolated static func resized(_ start: NSRect, edges: PreviewEdges, delta: CGSize, ratio: CGFloat,
                                    header: CGFloat, bounds: CGSize) -> NSRect {
        let sx: CGFloat = edges.contains(.left) ? -1 : edges.contains(.right) ? 1 : 0
        let sy: CGFloat = edges.contains(.bottom) ? -1 : edges.contains(.top) ? 1 : 0
        let byX = sx * delta.width
        let byY = sy * delta.height * ratio
        // за угол — по тому направлению, куда тянут сильнее
        let grow = sx == 0 ? byY : sy == 0 ? byX : (abs(byX) >= abs(byY) ? byX : byY)
        let width = clampedWidth(start.width + grow, ratio: ratio, bounds: bounds, header: header)
        let height = (width / ratio).rounded() + header
        let x = edges.contains(.left) ? start.maxX - width : start.minX
        let y = edges.contains(.top) && !edges.contains(.bottom) ? start.minY : start.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// Все окна просмотра: открытое из панели (одно) и закреплённые (сколько угодно).
@MainActor
final class ClipPreviews {
    /// Открыто из панели по ⌘1: закрывается кликом мимо и вместе с панелью.
    private(set) var transient: ClipPreviewWindow?
    /// Закреплённые и откреплённые потом: живут сами по себе.
    private(set) var detached: [ClipPreviewWindow] = []
    /// Рамка списка буфера: над ним открывается просмотр.
    weak var anchor: NSView?
    /// Окно из панели закрылось само (клик мимо, скрытие панели, закрепление) — панели забыть его.
    var onTransientGone: () -> Void = {}
    /// Меню правого клика по картинке этого окна.
    var menuItems: (ClipPreviewWindow) -> (leading: [NSMenuItem], trailing: [NSMenuItem]) = { _ in ([], []) }
    private var mouseMonitor: Any?
    /// Клики в других приложениях: незакреплённое окно без панели закрывается и ими.
    private var globalMouseMonitor: Any?
    private var hideObserver: NSObjectProtocol?
    /// Клик мимо закрыл просмотр этой картинки: клик по её же миниатюре не должен тут же открыть его снова.
    private var closedByClick: (id: UUID, at: Date)?

    var all: [ClipPreviewWindow] { (transient.map { [$0] } ?? []) + detached }

    func window(for nsWindow: NSWindow?) -> ClipPreviewWindow? {
        (nsWindow as? ClipPreviewPanel)?.preview
    }

    func isTransient(_ preview: ClipPreviewWindow) -> Bool { preview === transient }

    /// Открыть из панели (прежний просмотр из панели закрывается).
    func show(_ model: ClipPreviewModel, lang: String, parent: NSWindow?) {
        // другая картинка вместо открытой: панель уже знает новую — не сбрасывать её
        if let old = transient { transient = nil; old.close() }
        let preview = makeWindow(model, lang: lang)
        transient = preview
        installMonitors()
        let anchorRect = anchor.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } }
        preview.show(over: anchorRect, parent: parent)
    }

    /// Открыть без панели (клик по миниатюре скриншота): окно по центру экрана, Hatch остаётся скрытым.
    /// Не закреплено — закроется кликом мимо, ⌘S закрепит.
    func showDetached(_ model: ClipPreviewModel, lang: String, in visible: NSRect) {
        let preview = makeWindow(model, lang: lang)
        detached.append(preview)
        installMonitors()
        preview.show(centeredIn: visible)
    }

    private func makeWindow(_ model: ClipPreviewModel, lang: String) -> ClipPreviewWindow {
        let preview = ClipPreviewWindow(model: model, lang: lang,
                                        onTogglePin: { [weak self] in self?.togglePinOfModel(model) },
                                        onClose: { [weak self] in self?.closeModel(model) })
        model.liveText.menuItems = { [weak self, weak preview] in
            guard let self, let preview else { return ([], []) }
            return self.menuItems(preview)
        }
        return preview
    }

    /// Панель больше не показывает просмотр (⌘1, Esc, выбор другого режима).
    func closeTransient() {
        guard let transient else { return }
        closeWindow(transient)
    }

    func close(_ preview: ClipPreviewWindow) {
        closeWindow(preview)
    }

    /// ⌘S в окне: закрепить поверх окон или открепить.
    func togglePin(_ preview: ClipPreviewWindow) {
        if preview.model.isPinned {
            preview.setPinned(false)
        } else {
            if preview === transient {
                transient = nil
                detached.append(preview)
                onTransientGone()
            }
            preview.setPinned(true)
        }
        installMonitors()
    }

    /// Фрагмент удалён — его окна закрываются.
    func closeAll(clipID: UUID) {
        all.filter { $0.model.clipID == clipID }.forEach(closeWindow)
    }

    func closedByClickJustNow(_ id: UUID) -> Bool {
        guard let closedByClick, closedByClick.id == id else { return false }
        return Date().timeIntervalSince(closedByClick.at) < 0.6
    }

    private func togglePinOfModel(_ model: ClipPreviewModel) {
        if let preview = all.first(where: { $0.model === model }) { togglePin(preview) }
    }

    private func closeModel(_ model: ClipPreviewModel) {
        if let preview = all.first(where: { $0.model === model }) { closeWindow(preview) }
    }

    private func closeWindow(_ preview: ClipPreviewWindow) {
        let wasTransient = preview === transient
        if wasTransient { transient = nil } else { detached.removeAll { $0 === preview } }
        preview.close()
        if wasTransient { onTransientGone() }
        if all.allSatisfy(\.model.isPinned) { removeMonitors() }
    }

    /// Незакреплённые окна закрываются кликом мимо и вместе с панелью.
    private func installMonitors() {
        guard mouseMonitor == nil, all.contains(where: { !$0.model.isPinned }) else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            for preview in self.all where !preview.model.isPinned && event.window !== preview.panel {
                if preview === self.transient { self.closedByClick = (preview.model.clipID, Date()) }
                self.closeWindow(preview)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.all.filter { !$0.model.isPinned }.forEach(self.closeWindow)
            }
        }
        hideObserver = NotificationCenter.default.addObserver(forName: .hatchDidHide, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.all.filter { !$0.model.isPinned }.forEach(self.closeWindow)
            }
        }
    }

    private func removeMonitors() {
        mouseMonitor.map(NSEvent.removeMonitor)
        mouseMonitor = nil
        globalMouseMonitor.map(NSEvent.removeMonitor)
        globalMouseMonitor = nil
        hideObserver.map(NotificationCenter.default.removeObserver)
        hideObserver = nil
    }
}

/// Невидимый слой за списком буфера: над ним открывается просмотр. Клики проходят насквозь.
struct ClipPreviewAnchor: NSViewRepresentable {
    let previews: ClipPreviews

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        previews.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { previews.anchor = view }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Содержимое окна: шапка и картинка во всё остальное место.
private struct ClipPreviewContent: View {
    let model: ClipPreviewModel
    let lang: String
    var onTogglePin: () -> Void
    var onClose: () -> Void
    var onResetSize: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ClipPreviewWindow.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            header
            LiveTextImage(image: model.image, controller: model.liveText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        Text(toast)
                            .font(.system(size: 12))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Tactile.toast, in: RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.toast)
        }
        .background(Tactile.surface)
        .clipShape(shape)
        .overlay(shape.strokeBorder(model.isPinned ? Tactile.clip.opacity(0.6) : Tactile.surfaceEdge))
    }

    private var header: some View {
        HStack(spacing: 10) {
            // подпись и подсказки — тоже «за что тянуть»: слой перетаскивания поверх них, под кнопками
            HStack(spacing: 10) {
                Text(model.caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                // узкое окно — подсказки прячутся, кнопки остаются
                ViewThatFits(in: .horizontal) {
                    hints
                    Color.clear.frame(width: 0, height: 0)
                }
                Spacer(minLength: 0)
            }
            .overlay { WindowDragArea(onDoubleClick: onResetSize) }
            button(model.isPinned ? "pin.fill" : "pin",
                   help: L.t(model.isPinned ? "preview_unpin_help" : "preview_pin_help", lang),
                   tint: model.isPinned ? Tactile.clip : nil, perform: onTogglePin)
            button("xmark", help: L.t("preview_close_help", lang), tint: nil, perform: onClose)
        }
        .padding(.leading, 11)
        // ✕ не под уголком изменения размера
        .padding(.trailing, PreviewResizeView.thickness)
        .frame(height: ClipPreviewWindow.headerHeight)
        .background { WindowDragArea(onDoubleClick: onResetSize) }
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.35)).frame(height: 1) }
    }

    /// Клавиши, которые работают прямо сейчас: с выделением — действия с текстом.
    private var hints: some View {
        let items: [(String, String)]
        if model.liveText.selectionShown {
            items = [("⌘C", "preview_hint_copy_text"), ("⌘V", "clip_insert"), ("Esc", "preview_hint_deselect")]
        } else if model.isPinned {
            items = [("↩", "clip_copy"), ("⌘S", "preview_hint_unpin"), ("⌘W", "preview_hint_close")]
        } else {
            items = [("↩", "clip_copy"), ("⌘↩", "clip_insert_path"), ("⌘S", "preview_hint_pin"), ("Esc", "preview_hint_close")]
        }
        return HStack(spacing: 10) {
            ForEach(items, id: \.0) { key, title in
                HStack(spacing: 4) {
                    KeyHint(key: key)
                    Text(L.t(title, lang)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
    }

    private func button(_ symbol: String, help: String, tint: Color?, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 22, height: 22)
                .background(tint.map { $0.opacity(0.16) } ?? .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Невидимая рамка поверх окна: в углах — изменение размера. Остальное проходит
/// к картинке (выделение текста) и шапке (перетаскивание).
final class PreviewResizeView: NSView {
    /// Зона угла — уголок-«L» вдоль двух краёв: толщина полосы и её длина от угла. Края между углами
    /// размер не меняют: там шапка (перетаскивание) и картинка (выделение текста), а размер и так
    /// меняется только в пропорциях — углов хватает.
    static let thickness: CGFloat = 10
    static let length: CGFloat = 27
    var onResize: (NSRect, PreviewEdges, CGSize) -> Void = { _, _, _ in }
    var onEnd: () -> Void = {}
    private var drag: (edges: PreviewEdges, mouse: NSPoint, frame: NSRect)?
    private var cursorShown = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static func edges(at point: NSPoint, in size: CGSize) -> PreviewEdges {
        let x: PreviewEdges = point.x <= length ? .left : point.x >= size.width - length ? .right : []
        let y: PreviewEdges = point.y <= length ? .top : point.y >= size.height - length ? .bottom : []
        guard !x.isEmpty, !y.isEmpty else { return [] }
        let nearSide = point.x <= thickness || point.x >= size.width - thickness
        let nearEnd = point.y <= thickness || point.y >= size.height - thickness
        return nearSide || nearEnd ? x.union(y) : []
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return Self.edges(at: local, in: bounds.size).isEmpty ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // окно не активирует приложение — курсор нужен и когда оно не ключевое
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func cursor(for edges: PreviewEdges) -> NSCursor? {
        let position: NSCursor.FrameResizePosition
        switch edges {
        case [.top, .left]: position = .topLeft
        case [.top, .right]: position = .topRight
        case [.bottom, .left]: position = .bottomLeft
        case [.bottom, .right]: position = .bottomRight
        default: return nil
        }
        return .frameResize(position: position, directions: .all)
    }

    override func mouseMoved(with event: NSEvent) {
        guard drag == nil else { return }
        let edges = Self.edges(at: convert(event.locationInWindow, from: nil), in: bounds.size)
        if let cursor = cursor(for: edges) {
            cursor.set()
            cursorShown = true
        } else if cursorShown {
            // свой курсор только в углах; внутри — курсор картинки (I-beam над текстом)
            NSCursor.arrow.set()
            cursorShown = false
        }
    }

    override func mouseExited(with event: NSEvent) {
        if drag == nil, cursorShown { NSCursor.arrow.set(); cursorShown = false }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let edges = Self.edges(at: convert(event.locationInWindow, from: nil), in: bounds.size)
        guard !edges.isEmpty else { return }
        drag = (edges, NSEvent.mouseLocation, window.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let mouse = NSEvent.mouseLocation
        cursor(for: drag.edges)?.set()
        onResize(drag.frame, drag.edges, CGSize(width: mouse.x - drag.mouse.x, height: mouse.y - drag.mouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        onEnd()
    }
}
