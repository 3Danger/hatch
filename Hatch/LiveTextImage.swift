import SwiftUI
import AppKit
import VisionKit

/// Выделение текста на картинке в просмотре буфера (⌘1), как в Просмотре и Фото: распознаёт сам macOS
/// (Live Text, VisionKit), на этом Mac. Окно просмотра спрашивает через него выделенное — для ⌘C, ⌘V, ⌘A и Esc.
@MainActor @Observable
final class LiveTextController {
    @ObservationIgnored fileprivate weak var overlay: ImageAnalysisOverlayView?
    /// Пункты Hatch для меню правого клика по картинке: до системных пунктов Live Text и после них.
    @ObservationIgnored var menuItems: () -> (leading: [NSMenuItem], trailing: [NSMenuItem]) = { ([], []) }
    /// Для шапки окна: есть ли выделение (подсказки клавиш меняются). Решения — по `hasSelection`.
    private(set) var selectionShown = false

    var selectedText: String {
        guard let overlay, overlay.hasActiveTextSelection else { return "" }
        return overlay.selectedText
    }

    var hasSelection: Bool { !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// ⌘A: весь распознанный текст. false — текста нет (или ещё не распознан).
    @discardableResult
    func selectAll() -> Bool {
        guard let overlay, !overlay.text.isEmpty else { return false }
        overlay.selectedRanges = [overlay.text.startIndex..<overlay.text.endIndex]
        refresh()
        return true
    }

    func resetSelection() {
        overlay?.resetSelection()
        refresh()
    }

    /// Выделение поменялось (мышью или клавишами) — обновить шапку.
    func refresh() {
        let shown = hasSelection
        if selectionShown != shown { selectionShown = shown }
    }
}

/// Картинка с распознаванием текста поверх: занимает всё место, что ей дали, пропорции сохраняются
/// (окно просмотра само держит размер по картинке).
struct LiveTextImage: NSViewRepresentable {
    let image: NSImage
    let controller: LiveTextController

    /// Размер картинки в просмотре: её собственный (в точках), уменьшенный до `maxSize`.
    static func fittedSize(_ size: CGSize, in maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, maxSize.width / size.width, maxSize.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        let overlay = ImageAnalysisOverlayView()
        overlay.delegate = context.coordinator
        overlay.trackingImageView = imageView
        overlay.preferredInteractionTypes = .textSelection
        // кнопка Live Text не нужна: текст выделяется сразу
        overlay.isSupplementaryInterfaceHidden = true
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        container.addSubview(overlay)
        context.coordinator.imageView = imageView
        context.coordinator.overlay = overlay
        controller.overlay = overlay
        context.coordinator.load(image)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        controller.overlay = context.coordinator.overlay
        if context.coordinator.image !== image { context.coordinator.load(image) }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        coordinator.task?.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, ImageAnalysisOverlayViewDelegate {
        let controller: LiveTextController
        weak var imageView: NSImageView?
        weak var overlay: ImageAnalysisOverlayView?
        var image: NSImage?
        var task: Task<Void, Never>?
        private static let analyzer = ImageAnalyzer()

        init(controller: LiveTextController) { self.controller = controller }

        func load(_ image: NSImage) {
            self.image = image
            task?.cancel()
            imageView?.image = image
            overlay?.analysis = nil
            guard ImageAnalyzer.isSupported else { return }
            task = Task { [weak self] in
                let configuration = ImageAnalyzer.Configuration([.text])
                guard let analysis = try? await Self.analyzer.analyze(image, orientation: .up, configuration: configuration),
                      !Task.isCancelled, let self, self.image === image else { return }
                self.overlay?.analysis = analysis
            }
        }

        // MARK: ImageAnalysisOverlayViewDelegate

        func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) { controller.refresh() }

        /// Правый клик по картинке — всегда меню (и там, где текста нет): в нём действия Hatch.
        func overlayView(_ overlayView: ImageAnalysisOverlayView, shouldShowMenuForEvent event: NSEvent,
                         atPoint point: CGPoint) -> Bool { true }

        /// Меню одно: пункты Hatch, системные пункты Live Text (кроме тех, что Hatch делает сам:
        /// копировать, поделиться), в конце «Удалить».
        func overlayView(_ overlayView: ImageAnalysisOverlayView, updatedMenuFor menu: NSMenu,
                         for event: NSEvent, at point: CGPoint) -> NSMenu {
            let result = NSMenu()
            result.autoenablesItems = false
            let ours = controller.menuItems()
            let system = menu.items.filter(Self.keepsSystemItem)
            menu.removeAllItems()
            for item in ours.leading + [.separator()] + system + [.separator()] + ours.trailing {
                // без двойных разделителей и разделителя первым
                if item.isSeparatorItem, result.items.last?.isSeparatorItem ?? true { continue }
                result.addItem(item)
            }
            if result.items.last?.isSeparatorItem == true { result.removeItem(at: result.numberOfItems - 1) }
            return result
        }

        /// Системные «Найти» и «Перевести» остаются; копирование и «Поделиться» — свои у Hatch.
        nonisolated static func keepsSystemItem(_ item: NSMenuItem) -> Bool {
            if item.isSeparatorItem { return true }
            let dropped = [ImageAnalysisOverlayView.MenuTag.copyImage, ImageAnalysisOverlayView.MenuTag.shareImage,
                           ImageAnalysisOverlayView.MenuTag.copySubject, ImageAnalysisOverlayView.MenuTag.shareSubject]
            if dropped.contains(item.tag) { return false }
            if let action = item.action, action == #selector(NSText.copy(_:)) { return false }
            if item.submenu != nil, item.title.localizedCaseInsensitiveContains("share")
                || item.title.localizedCaseInsensitiveContains("поделиться") { return false }
            return true
        }
    }
}

/// Пункт меню с действием-замыканием (меню правого клика по картинке собирается в AppKit).
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    @objc private func runHandler() { handler() }
}
