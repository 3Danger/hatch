import AppKit
import SwiftUI

extension Notification.Name {
    /// Панель показана — можно ставить фокус в поле ввода.
    static let hatchDidShow = Notification.Name("hatch.didShow")
}

/// Панель без системной рамки: форму и стекло рисует SwiftUI.
/// Borderless-окно по умолчанию не принимает клавиатуру — разрешаем явно.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Плавающая неактивирующая панель для ввода команд.
/// Скрывается по клику в другом приложении; запоминает, куда её передвинули.
/// Высота меняется по содержимому, верхний край при этом стоит на месте.
final class FloatingWindowController {
    private let panel: NSPanel
    private let rootView: AnyView
    private let defaults: UserDefaults
    /// Верхний левый угол: при смене высоты он не двигается, в отличие от origin (нижнего левого).
    private static let topLeftKey = "panel.topLeft"
    /// Сдвиг окна самим приложением — не путать с перетаскиванием пользователем.
    private var isPositioning = false
    /// Где держать верхний край, когда окно меняет высоту.
    private var anchoredTop: CGFloat?
    private var outsideClickMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    init<V: View>(rootView: V, defaults: UserDefaults = .standard) {
        self.rootView = AnyView(rootView)
        self.defaults = defaults

        // Без .titled: иначе вокруг стекла видна светлая системная рамка и полоса заголовка.
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                              styleMask: [.nonactivatingPanel, .borderless],
                              backing: .buffered,
                              defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // Окно двигает WindowDragArea под стеклом (сам, по событиям мыши). Системное «за фон»
        // с SwiftUI-содержимым не работает, а жест SwiftUI и performDrag срабатывали через раз.
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Системная тень идёт по прямоугольнику окна и рисует светлую обводку по краям —
        // поверх скруглённого стекла это выглядит как артефакт. Тень рисует сама панель.
        panel.hasShadow = false

        let hosting = NSHostingView(rootView: self.rootView)
        // окно принимает размер, который просит SwiftUI-содержимое
        hosting.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        panel.contentView = hosting

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) {
            [weak self] _ in self?.userMovedPanel()
        })
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) {
            [weak self] _ in self?.keepTopAfterResize()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        removeOutsideClickMonitor()
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
        NotificationCenter.default.post(name: .hatchDidShow, object: nil)
    }

    func hide() {
        removeOutsideClickMonitor()
        // всплывающие окна (меню папки, избранное) закрываются вместе с панелью
        NotificationCenter.default.post(name: .hatchDidHide, object: nil)
        panel.orderOut(nil)
        // раскладка общая для всех приложений — возвращаем ту, что была до панели
        KeyboardLayoutSwitcher.shared.restore()
    }

    private func positionPanel() {
        guard let main = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        let savedOrigin = defaults.string(forKey: Self.topLeftKey)
            .map(NSPointFromString)
            .map { NSPoint(x: $0.x, y: $0.y - size.height) }
        let origin = PanelPlacement.origin(saved: savedOrigin,
                                           panelSize: size,
                                           visibleFrames: NSScreen.screens.map(\.visibleFrame),
                                           main: main)
        isPositioning = true
        panel.setFrameOrigin(origin)
        isPositioning = false
        anchoredTop = origin.y + size.height
    }

    /// Пользователь перетащил панель — запоминаем новый верхний левый угол.
    private func userMovedPanel() {
        guard !isPositioning else { return }
        let frame = panel.frame
        anchoredTop = frame.maxY
        defaults.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.topLeftKey)
    }

    /// AppKit меняет высоту, сохраняя нижний край; возвращаем на место верхний.
    private func keepTopAfterResize() {
        if let top = anchoredTop, abs(panel.frame.maxY - top) > 0.5 {
            isPositioning = true
            panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
            isPositioning = false
        }
    }

    /// Глобальный монитор видит только клики в других приложениях: клики по панели,
    /// её диалогам и меню в строке состояния его не задевают. Прав Accessibility не требует.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeOutsideClickMonitor() {
        outsideClickMonitor.map(NSEvent.removeMonitor)
        outsideClickMonitor = nil
    }
}
