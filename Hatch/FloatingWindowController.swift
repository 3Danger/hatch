import AppKit
import SwiftUI

extension Notification.Name {
    /// Панель показана — можно ставить фокус в поле ввода.
    static let hatchDidShow = Notification.Name("hatch.didShow")
    /// Скрыть панель: после запуска приложения или копирования результата из поля ввода.
    static let hatchRequestHide = Notification.Name("hatch.requestHide")
    /// Показать панель: ⌘V и ⌘↩ в закреплённом просмотре картинки, когда Hatch скрыт.
    static let hatchRequestShow = Notification.Name("hatch.requestShow")
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
    private var spaceObserver: NSObjectProtocol?

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
        // false: с «только если нужно» панель, отдав клавиатуру всплывающему окну (дерево папок,
        // избранное), сбрасывала фокус поля ввода — после Esc курсора не было нигде
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        // показывается на текущем рабочем столе, в том числе поверх приложения во весь экран
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        observers.append(center.addObserver(forName: .hatchRequestHide, object: nil, queue: .main) {
            [weak self] _ in self?.hide()
        })
        observers.append(center.addObserver(forName: .hatchRequestShow, object: nil, queue: .main) {
            [weak self] _ in self?.show()
        })
        // сменили рабочий стол — панель исчезает, как Spotlight; хоткей откроет её уже на новом столе
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.hide()
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        spaceObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
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
            // «Разрешить» в системном запросе — не клик мимо: панель остаётся, команда, ждавшая
            // разрешения, продолжает работать на виду
            if Self.clickedSystemPrompt() { return }
            self?.hide()
        }
    }

    /// Системные окна, клик по которым не «мимо» панели: запросы разрешений (папки, уведомления,
    /// универсальный доступ), пароль администратора, предупреждения о запуске приложений.
    static let systemPromptBundleIDs: Set<String> = [
        "com.apple.UserNotificationCenter",          // разрешения на папки, камеру, контакты…
        "com.apple.notificationcenterui",            // запрос уведомлений
        "com.apple.SecurityAgent",                   // пароль администратора
        "com.apple.coreservices.uiagent",            // «приложение загружено из интернета»
        "com.apple.accessibility.universalAccessAuthWarn", // универсальный доступ
        "com.apple.UniversalAccessControl",
    ]

    /// Чьё окно под курсором — системный запрос? Видно только владельца окна, не его содержимое:
    /// разрешение на запись экрана для этого не нужно.
    private static func clickedSystemPrompt() -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        guard let pid = windowOwner(at: NSEvent.mouseLocation, windows: windows,
                                    primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0) else { return false }
        return systemPromptBundleIDs.contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "")
    }

    /// Процесс верхнего видимого окна в точке экрана. `windows` — как отдаёт CGWindowList (спереди назад,
    /// начало координат сверху слева), `point` — как у NSEvent (снизу слева).
    static func windowOwner(at point: NSPoint, windows: [[String: Any]], primaryScreenHeight: CGFloat) -> pid_t? {
        let flipped = CGPoint(x: point.x, y: primaryScreenHeight - point.y)
        for info in windows {
            guard let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.contains(flipped) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }
            return info[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    private func removeOutsideClickMonitor() {
        outsideClickMonitor.map(NSEvent.removeMonitor)
        outsideClickMonitor = nil
    }
}
