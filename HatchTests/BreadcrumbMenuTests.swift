import XCTest
import SwiftUI
import Observation
@testable import Hatch

/// Меню папки по правому клику открывается у любой папки пути — и после перехода глубже.
@MainActor
final class BreadcrumbMenuTests: XCTestCase {
    @Observable final class Model { var path = "/usr/local" }

    private struct Host: View {
        let model: Model
        var body: some View {
            DirectoryBreadcrumbsView(path: model.path, recent: [], lang: "ru", onNavigate: { model.path = $0 })
                .frame(width: 600)
                .padding(10)
        }
    }

    private func anchors(in view: NSView) -> [PopupAnchorView] {
        var found: [PopupAnchorView] = []
        func walk(_ view: NSView) {
            if let anchor = view as? PopupAnchorView { found.append(anchor) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    private func rightClick(at anchor: PopupAnchorView, in window: NSWindow) -> NSEvent {
        let frame = anchor.convert(anchor.bounds, to: nil)
        return NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: frame.midX, y: frame.midY),
                                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                  clickCount: 1, pressure: 1)!
    }

    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    /// У каждой папки ровно один якорь берёт правый клик, и он открывает меню.
    private func assertEveryCrumbOpensMenu(_ host: NSView, _ window: NSWindow, crumbs: Int,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let all = anchors(in: host)
        let menus = all.filter { $0.onSecondaryClick != nil }
        XCTAssertEqual(menus.count, crumbs, "по якорю меню на папку", file: file, line: line)
        for anchor in menus {
            let event = rightClick(at: anchor, in: window)
            // никакой другой якорь в той же точке клик не перехватывает
            XCTAssertEqual(all.filter { $0.handlesSecondaryClick(event) }, [anchor], file: file, line: line)
            anchor.onSecondaryClick?(NSPoint(x: 300, y: 300))
            spin()
            XCTAssertEqual(window.childWindows?.count, 1, "меню открылось", file: file, line: line)
            NotificationCenter.default.post(name: .hatchDidHide, object: nil)
            spin()
            XCTAssertEqual(window.childWindows?.count ?? 0, 0, file: file, line: line)
        }
    }

    func testMenuOpensOnEveryCrumbAfterNavigatingDeeper() {
        let model = Model()
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        assertEveryCrumbOpensMenu(host, window, crumbs: 3) // / › usr › local

        model.path = "/usr/local/bin"
        spin()
        assertEveryCrumbOpensMenu(host, window, crumbs: 4)
    }
}
