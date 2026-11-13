import AppKit
import SwiftUI

extension Notification.Name {
    /// Панель скрыта — всплывающие окна (меню папки, избранное) закрываются вместе с ней.
    static let hatchDidHide = Notification.Name("hatch.didHide")
}

/// Где показать всплывающее окно относительно того, к чему оно привязано.
enum PopupPlacement: Equatable {
    /// Под элементом, со стрелкой на него (как всплывающее окно macOS).
    case below
    /// Верхним левым углом у курсора (контекстное меню).
    case atMouse
    /// Поверх элемента, верхние края вровень, по центру (настройки поверх панели).
    case overTop
}

/// Всплывающее окно Hatch: сплошное, со своей тенью. Системные меню и всплывающие окна
/// macOS 26 рисуются стеклом (сквозь них просвечивает фон), а интерфейс Hatch — без стекла.
final class PopupPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Esc, если его не обработало содержимое.
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// Одно всплывающее окно: показывает, двигает к якорю, закрывает по клику мимо, Esc и скрытию панели.
@MainActor
final class PopupController {
    /// Запас окна под тень карточки.
    static let margin: CGFloat = 22
    /// Зазор между элементом и карточкой. Стрелки нет: она наезжала на подпись элемента.
    static let gap: CGFloat = 6

    private var window: PopupPanel?
    private var hosting: NSHostingView<AnyView>?
    private var monitor: Any?
    private var hideObserver: NSObjectProtocol?
    private weak var parent: NSWindow?
    /// Элемент, к которому привязано окно: клик по нему (★ ещё раз) не закрывает окно монитором —
    /// это делает сам элемент, иначе окно закрылось бы и тут же открылось снова.
    weak var anchorView: NSView?
    /// Окно должно быть открыто: показ откладывается до конца раскладки, а к тому времени его могли закрыть.
    var wantsShown = false
    var onDismiss: () -> Void = {}

    var isShown: Bool { window != nil }

    /// - Parameters:
    ///   - anchor: рамка элемента в координатах экрана;
    ///   - content: карточка с содержимым.
    func present(anchor: NSRect, placement: PopupPlacement, mouse: NSPoint?, parent: NSWindow?,
                 content: @escaping () -> AnyView) {
        let firstShow = window == nil
        if firstShow { create(parent: parent) }
        guard let window, let hosting else { return }

        hosting.rootView = content()
        let size = hosting.fittingSize
        let screen = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
        var origin: NSPoint
        switch placement {
        case .below:
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - Self.gap - size.height + Self.margin)
        case .atMouse:
            let point = mouse ?? NSPoint(x: anchor.minX, y: anchor.minY)
            origin = NSPoint(x: point.x - Self.margin + 2, y: point.y - size.height + Self.margin - 2)
        case .overTop:
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - size.height + Self.margin)
        }
        // не за край экрана (тень может заходить за него)
        origin.x = min(max(origin.x, screen.minX - Self.margin), screen.maxX - size.width + Self.margin)
        origin.y = max(origin.y, screen.minY - Self.margin)
        origin.y = min(origin.y, screen.maxY - size.height + Self.margin)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        if firstShow {
            parent?.addChildWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Обновить содержимое открытого окна (например, из избранного убрали пункт) без перемещения стрелки.
    func dismiss() {
        guard let window else { return }
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        hideObserver.map(NotificationCenter.default.removeObserver)
        hideObserver = nil
        parent?.removeChildWindow(window)
        window.orderOut(nil)
        self.window = nil
        hosting = nil
        // клавиатура — обратно панели
        if let parent, parent.isVisible { parent.makeKey() }
        onDismiss()
    }

    private func create(parent: NSWindow?) {
        self.parent = parent
        let window = PopupPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false // тень рисует карточка: системная шла бы по прямоугольнику окна
        window.level = parent?.level ?? .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.onCancel = { [weak self] in self?.dismiss() }
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        window.contentView = hosting
        if let appearance = parent?.effectiveAppearance { window.appearance = appearance }
        self.window = window
        self.hosting = hosting

        // клик мимо окна закрывает его; сам клик идёт дальше как обычно
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
            [weak self] event in
            guard let self, self.window != nil else { return event }
            if !self.owns(event.window), !self.isOnAnchor(event) { self.dismiss() }
            return event
        }
        hideObserver = NotificationCenter.default.addObserver(forName: .hatchDidHide, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.dismiss() }
        }
    }
}

extension PopupController {
    /// Клик в самом окне или в окне, открытом из него (меню папки поверх дерева), — свой:
    /// дерево не закрывается, пока работаешь с его меню.
    func owns(_ other: NSWindow?) -> Bool {
        var current = other
        while let candidate = current {
            if candidate === window { return true }
            current = candidate.parent
        }
        return false
    }

    fileprivate func isOnAnchor(_ event: NSEvent) -> Bool {
        guard let anchorView, event.window === anchorView.window, event.type == .leftMouseDown else { return false }
        return anchorView.bounds.contains(anchorView.convert(event.locationInWindow, from: nil))
    }
}

// MARK: - Привязка к элементу SwiftUI

/// Невидимый якорь за элементом: знает его место на экране и ловит правый клик по нему.
private struct PopupAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let placement: PopupPlacement
    let onSecondaryClick: (() -> Void)?
    let content: (PopupContext) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onSecondaryClick = secondaryClickHandler(context.coordinator)
        return view
    }

    /// Правый клик ловит только якорь со своим меню. У элемента бывает несколько якорей
    /// (список папок по левому клику и меню по правому): если бы клик ловили все, якорь
    /// без меню съедал бы его, и меню открывалось через раз — смотря чей обработчик первый.
    private func secondaryClickHandler(_ coordinator: Coordinator) -> ((NSPoint) -> Void)? {
        guard let onSecondaryClick else { return nil }
        return { [weak coordinator] point in
            coordinator?.mouse = point
            onSecondaryClick()
        }
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        let coordinator = context.coordinator
        view.onSecondaryClick = secondaryClickHandler(coordinator)
        coordinator.controller.onDismiss = { if isPresented { isPresented = false } }
        coordinator.controller.anchorView = view
        coordinator.controller.wantsShown = isPresented
        view.onAttach = nil
        guard isPresented else {
            if coordinator.controller.isShown { coordinator.controller.dismiss() }
            return
        }
        let scheme = context.environment.colorScheme
        let popupContext = PopupContext(anchorView: view, dismiss: { [weak coordinator] in coordinator?.controller.dismiss() })
        let build = content
        let placement = placement
        let show = { [weak view] in
            guard let view, let window = view.window else { return }
            let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
            // показываем после текущего прохода раскладки: окно меряет SwiftUI-содержимое.
            // К тому времени элемент мог пропасть (путь стал короче) — тогда окно осталось бы без хозяина.
            DispatchQueue.main.async { [weak view] in
                guard coordinator.controller.wantsShown, view?.window != nil else { return }
                coordinator.controller.present(anchor: anchor, placement: placement, mouse: coordinator.mouse,
                                               parent: window) {
                    AnyView(build(popupContext).environment(\.colorScheme, scheme))
                }
            }
        }
        // элемент только что появился и ещё не в окне (папка из-за «…», путь раскрывается) — покажем,
        // когда встанет: иначе окно не открылось бы, пока что-нибудь ещё не обновит якорь
        if view.window == nil { view.onAttach = show } else { show() }
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        coordinator.controller.wantsShown = false
        coordinator.controller.dismiss()
    }

    @MainActor
    final class Coordinator {
        let controller = PopupController()
        var mouse: NSPoint?
    }

    typealias AnchorView = PopupAnchorView
}

/// Якорь всплывающего окна: клики проходят насквозь, правый клик (или ⌃-клик) по элементу
/// открывает своё меню вместо системного.
final class PopupAnchorView: NSView {
    var onSecondaryClick: ((NSPoint) -> Void)?
    /// Окно надо показать, а якорь ещё не в окне — показать, как только встанет.
    var onAttach: (() -> Void)?
    private var monitor: Any?

    // клики проходят насквозь: якорь только знает рамку элемента
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        guard window != nil else { return }
        if let attach = onAttach { onAttach = nil; attach() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, self.handlesSecondaryClick(event) else { return event }
            self.onSecondaryClick?(NSEvent.mouseLocation)
            return nil
        }
    }

    /// Правый клик или ⌃-клик внутри якоря, у которого есть своё меню.
    func handlesSecondaryClick(_ event: NSEvent) -> Bool {
        guard onSecondaryClick != nil, event.window === window,
              event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override var isFlipped: Bool { true }
}

/// Что всплывающее окно знает о том, откуда его открыли.
struct PopupContext {
    /// Элемент, к которому привязано окно (для «Поделиться…»).
    let anchorView: NSView
    let dismiss: () -> Void
}

extension View {
    /// Своё всплывающее окно у элемента — сплошное, без стекла. `onSecondaryClick` — открыть по правому клику.
    func hatchPopup<Content: View>(isPresented: Binding<Bool>, placement: PopupPlacement = .below,
                                   onSecondaryClick: (() -> Void)? = nil,
                                   @ViewBuilder content: @escaping (PopupContext) -> Content) -> some View {
        background(PopupAnchor(isPresented: isPresented, placement: placement, onSecondaryClick: onSecondaryClick,
                               content: { AnyView(content($0)) }))
    }
}

// MARK: - Карточки

/// Карточка всплывающего окна: сплошная, кромка, тень (без стрелки — она наезжала на подпись элемента).
struct PopupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        content
            .background { shape.fill(Tactile.surface) }
            .overlay { shape.strokeBorder(Tactile.surfaceEdge) }
            .overlay { shape.inset(by: 1).stroke(LinearGradient(colors: [.white.opacity(0.08), .clear],
                                                               startPoint: .top, endPoint: .center), lineWidth: 1) }
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 18, y: 12)
            .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
            .padding(PopupController.margin)
            .fixedSize()
    }
}

/// Карточка контекстного меню: плотнее и с меньшим скруглением, как меню macOS, но сплошная.
struct MenuCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .circular)
        content
            .padding(5)
            .background { shape.fill(Tactile.menu) }
            .overlay { shape.strokeBorder(Tactile.menuEdge) }
            .compositingGroup()
            .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
            .padding(PopupController.margin)
            .fixedSize()
    }
}
