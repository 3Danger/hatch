import SwiftUI
import AppKit

/// Невидимая полоса у края панели: курсор изменения размера и перетаскивание.
/// Смещение — в координатах экрана: окно меняет размер прямо во время перетаскивания,
/// и координаты внутри него поехали бы вместе с ним.
struct PanelResizeHandle: NSViewRepresentable {
    let edges: ResizeEdges
    var onBegin: (NSWindow?) -> Void
    /// Смещение мыши от начала: `width` — вправо, `height` — вниз.
    var onDrag: (CGSize) -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        update(view)
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) { update(view) }

    private func update(_ view: HandleView) {
        view.edges = edges
        view.onBegin = onBegin
        view.onDrag = onDrag
        view.onEnd = onEnd
    }

    final class HandleView: NSView {
        var edges: ResizeEdges = .right
        var onBegin: (NSWindow?) -> Void = { _ in }
        var onDrag: (CGSize) -> Void = { _ in }
        var onEnd: () -> Void = {}
        private var start: NSPoint?

        // иначе панель (её можно двигать за фон) уедет вместо изменения размера
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var cursor: NSCursor {
            switch edges {
            case .right: return .resizeLeftRight
            case .bottom: return .resizeUpDown
            default: return .frameResize(position: .bottomRight, directions: .all)
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // панель не активирует приложение — курсор нужен и когда окно не ключевое
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func cursorUpdate(with event: NSEvent) { cursor.set() }
        override func mouseEntered(with event: NSEvent) { cursor.set() }
        override func mouseExited(with event: NSEvent) { if start == nil { NSCursor.arrow.set() } }

        override func mouseDown(with event: NSEvent) {
            start = NSEvent.mouseLocation
            onBegin(window)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let now = NSEvent.mouseLocation
            cursor.set()
            onDrag(CGSize(width: now.x - start.x, height: start.y - now.y))
        }

        override func mouseUp(with event: NSEvent) {
            start = nil
            onEnd()
        }
    }
}
