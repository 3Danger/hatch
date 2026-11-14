import SwiftUI
import AppKit

// MARK: - Каталог действий

/// Действия кнопок Hatch: что сделает нажатие и какой клавишей. Один источник для подсказок
/// при наведении, клавиш в меню «⋯» и шпаргалке ⌘/ — текст и клавиша не разъезжаются.
enum HatchAction: Hashable {
    // блок команды
    case copyOutput, rerun, stop, blockMenu, addFilter
    // запись буфера
    case pasteInto(String?), copyClipToPaste, copyClipOnly, insertClip, insertPath, previewClip
    case formatOn, formatOff, pinClip, unpinClip, deleteClip
    // поле ввода и режимы
    case favorites, settings, modeCommands, modeSearch, modeClipboard
    // окно просмотра
    case copyAll, pinWindow, unpinWindow, closePreview(pinned: Bool)

    /// Клавиша действия; nil — только мышью.
    var key: String? {
        switch self {
        case .copyOutput, .copyClipOnly: "⌘C"
        case .rerun: "⌘R"
        case .stop: "⌃C"
        case .blockMenu, .addFilter: nil
        case .pasteInto, .copyClipToPaste, .copyAll: "↩"
        case .insertClip, .insertPath: "⌘↩"
        case .previewClip: "⌘Y"
        case .formatOn, .formatOff: "⇧⌘R"
        case .pinClip, .unpinClip, .pinWindow, .unpinWindow: "⌘S"
        case .deleteClip: "⌘⌫"
        case .favorites: "⌘E"
        case .settings: "⌘,"
        case .modeCommands: "⌘1"
        case .modeSearch: "⌘2"
        case .modeClipboard: "⌘3"
        case .closePreview(let pinned): pinned ? "⌘W" : "Esc"
        }
    }

    /// Что произойдёт по нажатию — с глагола, для подсказки.
    func text(_ lang: String) -> String {
        let t = { (ru: String, en: String) in lang == "ru" ? ru : en }
        switch self {
        case .copyOutput: return t("Скопировать вывод", "Copy the output")
        case .rerun: return t("Запустить ещё раз в этом блоке", "Run again in this block")
        case .stop: return t("Остановить команду", "Stop the command")
        case .blockMenu: return t("Ещё: команда, фильтр, избранное, закрепить, удалить",
                                  "More: command, filter, favorites, pin, delete")
        case .addFilter: return t("grep, sort, jq к выводу — без перезапуска", "grep, sort, jq on the output — no re-run")
        case .pasteInto(let app):
            if let app { return String(format: t("Вставить в %@", "Paste into %@"), app) }
            return t("Вставить в приложение, где вы были", "Paste into the app you were in")
        case .copyClipToPaste: return t("Скопировать — вставите сами", "Copy — then paste it yourself")
        case .copyClipOnly: return t("Только скопировать", "Only copy")
        case .insertClip: return t("В поле команды", "Into the command field")
        case .insertPath: return t("Путь к файлу — в поле команды", "File path into the command field")
        case .previewClip: return t("Открыть целиком", "Open in full")
        case .formatOn: return t("Показать отформатированным", "Show formatted")
        case .formatOff: return t("Показать как есть", "Show as is")
        case .pinClip: return t("Закрепить — очистка не удалит", "Pin — clearing keeps it")
        case .unpinClip: return t("Открепить — вернётся в «Недавние»", "Unpin — back to Recent")
        case .deleteClip: return t("Удалить запись", "Delete the item")
        case .favorites: return t("Избранные папки и команды", "Favorite folders and commands")
        case .settings: return t("Настройки", "Settings")
        case .modeCommands: return t("Команды", "Commands")
        case .modeSearch: return t("Поиск по командам и выводу", "Search commands and output")
        case .modeClipboard: return t("Буфер обмена", "Clipboard")
        case .copyAll: return t("Скопировать всё, как видно", "Copy all, as shown")
        case .pinWindow: return t("Поверх всех окон", "Keep on top of all windows")
        case .unpinWindow: return t("Не держать поверх окон", "Stop keeping on top")
        case .closePreview: return t("Закрыть", "Close")
        }
    }

    func tip(_ lang: String) -> HatchTip { HatchTip(text: text(lang), key: key) }
}

/// Подсказка при наведении: что сделает нажатие и клавиша (если есть).
struct HatchTip: Equatable {
    let text: String
    var key: String?
}

// MARK: - Модификатор

extension View {
    /// Подсказка Hatch при наведении: тёмный тост над элементом через треть секунды
    /// (вместо системной `.help`, которая ждёт полторы-две секунды). nil — без подсказки.
    func hatchTip(_ tip: HatchTip?) -> some View {
        background(TipAnchor(tip: tip))
            .accessibilityHint(tip?.text ?? "")
    }

    func hatchTip(_ action: HatchAction, _ lang: String) -> some View {
        hatchTip(action.tip(lang))
    }
}

/// Невидимая подложка элемента: знает его рамку на экране и ловит вход и выход мыши.
private struct TipAnchor: NSViewRepresentable {
    let tip: HatchTip?

    func makeNSView(context: Context) -> TipAnchorView { TipAnchorView() }

    func updateNSView(_ view: TipAnchorView, context: Context) {
        view.tip = tip
    }
}

final class TipAnchorView: NSView {
    var tip: HatchTip? {
        didSet { if tip != oldValue { TipCenter.shared.update(from: self) } }
    }
    private var tracking: NSTrackingArea?

    // клики проходят насквозь — подложка только смотрит
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        tracking.map(removeTrackingArea)
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { TipCenter.shared.enter(self) }
    override func mouseExited(with event: NSEvent) { TipCenter.shared.exit(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { TipCenter.shared.exit(self) }
    }

    /// Рамка элемента на экране.
    var screenFrame: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }
}

// MARK: - Окно подсказки

/// Одна подсказка на всё приложение — своим окном: не обрезается краем панели или окна просмотра.
/// Появляется через 0,35 с; пока подсказка только что была видна, на соседней кнопке — сразу.
final class TipCenter {
    static let shared = TipCenter()
    static let delay: TimeInterval = 0.35
    /// Сколько после ухода с кнопки соседняя показывается без задержки.
    static let warmWindow: TimeInterval = 0.4

    private weak var anchor: TipAnchorView?
    private var pending: DispatchWorkItem?
    private var lastHidden = Date.distantPast
    private var clickMonitor: Any?
    private lazy var panel: NSPanel = makePanel()
    private let hosting = NSHostingView(rootView: TipBubble(tip: HatchTip(text: "")))

    private(set) var shownTip: HatchTip?

    func enter(_ view: TipAnchorView) {
        guard view.tip != nil else { return }
        anchor = view
        pending?.cancel()
        let warm = panel.isVisible || Date().timeIntervalSince(lastHidden) < Self.warmWindow
        if warm { show() } else {
            let work = DispatchWorkItem { [weak self] in self?.show() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
        }
        installClickMonitor()
    }

    func exit(_ view: TipAnchorView) {
        guard anchor === view else { return }
        hide()
    }

    /// Текст поменялся, пока мышь над элементом (закрепили — «Открепить»).
    func update(from view: TipAnchorView) {
        guard anchor === view, panel.isVisible else { return }
        if view.tip == nil { hide() } else { show() }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        anchor = nil
        if panel.isVisible { lastHidden = Date() }
        panel.orderOut(nil)
        shownTip = nil
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
    }

    private func show() {
        guard let anchor, let tip = anchor.tip, let frame = anchor.screenFrame,
              anchor.window?.isVisible == true else { hide(); return }
        hosting.rootView = TipBubble(tip: tip)
        let size = hosting.fittingSize
        let visible = (anchor.window?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        panel.setFrame(NSRect(origin: Self.origin(for: size, above: frame, in: visible, gap: -4), size: size), display: true)
        panel.orderFrontRegardless()
        shownTip = tip
    }

    /// Над элементом по центру; у края экрана — сдвиг внутрь; сверху места нет — под элементом.
    static func origin(for size: CGSize, above frame: NSRect, in visible: NSRect, gap: CGFloat = 6) -> NSPoint {
        var x = frame.midX - size.width / 2
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        var y = frame.maxY + gap
        if y + size.height > visible.maxY { y = frame.minY - gap - size.height }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    /// Нажали — подсказка больше не нужна (и не висит над тем, что открылось).
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.hide()
            return event
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // выше окон просмотра и всплывающих окон Hatch
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        return panel
    }
}

/// Тост подсказки — как «Скопировано: …» и «✓ В буфере»: тёмный, скругление 7, клавиша справа.
struct TipBubble: View {
    let tip: HatchTip

    var body: some View {
        HStack(spacing: 8) {
            Text(tip.text)
                .font(.system(size: 12))
                .foregroundStyle(Tactile.keyText)
                .lineLimit(1)
            if let key = tip.key { KeyHint(key: key) }
        }
        .padding(.leading, 10)
        .padding(.trailing, tip.key == nil ? 10 : 6)
        .frame(height: 26)
        .background(Tactile.toast, in: RoundedRectangle(cornerRadius: 7, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .circular).strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
        .padding(10) // место под тень
        .fixedSize()
    }
}
