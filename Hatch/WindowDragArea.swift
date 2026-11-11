import SwiftUI
import AppKit

/// Слой под содержимым панели: за пустые места окно перетаскивается.
/// Двигаем сами, по событиям мыши: жест SwiftUI (`WindowDragGesture`) и передача переноса
/// системе (`performDrag`) на этой панели срабатывали через раз, а системное «двигать за фон»
/// (`isMovableByWindowBackground`) с SwiftUI-содержимым не работает вовсе.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        /// Где нажали (в координатах экрана) и где тогда было окно.
        private var start: (mouse: NSPoint, origin: NSPoint)?

        // первый клик по неактивной панели тоже двигает её
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (NSEvent.mouseLocation, window.frame.origin)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let window else { return }
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                          y: start.origin.y + mouse.y - start.mouse.y))
        }

        override func mouseUp(with event: NSEvent) {
            start = nil
        }
    }
}
