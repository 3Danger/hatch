import XCTest
import SwiftUI
@testable import Hatch

/// Своё всплывающее окно (вместо стеклянного системного): где открывается и когда закрывается.
@MainActor
final class PopupPanelTests: XCTestCase {
    private func parentWindow() -> NSWindow {
        let window = NSPanel(contentRect: NSRect(x: 200, y: 300, width: 600, height: 400),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.orderFront(nil)
        return window
    }

    private func card() -> AnyView {
        AnyView(PopupCard { Color.red.frame(width: 200, height: 100) })
    }

    /// Под элементом: карточка по центру под ним, с зазором; окно — дочернее у панели.
    func testBelowPlacementCentersUnderAnchor() throws {
        let parent = parentWindow()
        let controller = PopupController()
        let anchor = NSRect(x: 500, y: 600, width: 28, height: 28)
        controller.present(anchor: anchor, placement: .below, mouse: nil, parent: parent) { self.card() }
        XCTAssertTrue(controller.isShown)
        let child = try XCTUnwrap(parent.childWindows?.first)
        XCTAssertEqual(child.frame.midX, anchor.midX, accuracy: 0.5)
        // верх карточки — под элементом, с зазором
        XCTAssertEqual(child.frame.maxY - PopupController.margin, anchor.minY - PopupController.gap, accuracy: 0.5)
        controller.dismiss()
        XCTAssertFalse(controller.isShown)
        XCTAssertTrue(parent.childWindows?.isEmpty ?? true)
    }

    /// Меню у курсора: верхний левый угол карточки — у курсора.
    func testMenuOpensAtMouse() throws {
        let parent = parentWindow()
        let controller = PopupController()
        let mouse = NSPoint(x: 400, y: 650)
        controller.present(anchor: .zero, placement: .atMouse, mouse: mouse, parent: parent) { self.card() }
        let child = try XCTUnwrap(parent.childWindows?.first)
        XCTAssertEqual(child.frame.minX + PopupController.margin, mouse.x + 2, accuracy: 0.5)
        XCTAssertEqual(child.frame.maxY - PopupController.margin, mouse.y - 2, accuracy: 0.5)
        controller.dismiss()
    }

    /// Панель скрылась — всплывающее окно закрывается вместе с ней и сообщает об этом.
    func testClosesWhenPanelHides() {
        let parent = parentWindow()
        let controller = PopupController()
        var dismissed = false
        controller.onDismiss = { dismissed = true }
        controller.present(anchor: NSRect(x: 300, y: 500, width: 20, height: 20), placement: .below, mouse: nil,
                           parent: parent) { self.card() }
        NotificationCenter.default.post(name: .hatchDidHide, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(controller.isShown)
        XCTAssertTrue(dismissed)
    }
}
