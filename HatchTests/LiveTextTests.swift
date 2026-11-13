import XCTest
import AppKit
import VisionKit
@testable import Hatch

/// Меню и размер просмотра картинки с выделением текста (Live Text).
@MainActor
final class LiveTextTests: XCTestCase {
    func testFittedSizeKeepsAspectAndNeverUpscales() {
        XCTAssertEqual(LiveTextImage.fittedSize(CGSize(width: 1800, height: 600), in: CGSize(width: 900, height: 600)),
                       CGSize(width: 900, height: 300))
        XCTAssertEqual(LiveTextImage.fittedSize(CGSize(width: 400, height: 1200), in: CGSize(width: 900, height: 600)),
                       CGSize(width: 200, height: 600))
        XCTAssertEqual(LiveTextImage.fittedSize(CGSize(width: 240, height: 120), in: CGSize(width: 900, height: 600)),
                       CGSize(width: 240, height: 120), "маленькая картинка не растягивается")
        XCTAssertEqual(LiveTextImage.fittedSize(.zero, in: CGSize(width: 900, height: 600)), .zero)
    }

    /// Меню одно: пункты Hatch, системные «Найти»/«Перевести», «Удалить» в конце; системное
    /// «Скопировать» и «Поделиться» убраны — у Hatch свои.
    func testMenuMergesHatchAndSystemItems() throws {
        let controller = LiveTextController()
        controller.menuItems = {
            ([ClosureMenuItem("Копировать выделенное") {}, .separator(), ClosureMenuItem("Копировать картинку") {}],
             [ClosureMenuItem("Удалить") {}])
        }
        let coordinator = LiveTextImage.Coordinator(controller: controller)
        let system = NSMenu()
        system.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        let copyImage = NSMenuItem(title: "Copy Image", action: nil, keyEquivalent: "")
        copyImage.tag = ImageAnalysisOverlayView.MenuTag.copyImage
        system.addItem(copyImage)
        system.addItem(.separator())
        let lookUp = NSMenuItem(title: "Look Up “HATCH”", action: nil, keyEquivalent: "")
        lookUp.tag = ImageAnalysisOverlayView.MenuTag.lookupItem
        system.addItem(lookUp)
        system.addItem(NSMenuItem(title: "Translate “HATCH”", action: nil, keyEquivalent: ""))
        let share = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        share.submenu = NSMenu()
        system.addItem(share)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = coordinator.overlayView(ImageAnalysisOverlayView(), updatedMenuFor: system, for: event, at: .zero)
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "—" : $0.title },
                       ["Копировать выделенное", "—", "Копировать картинку", "—", "Look Up “HATCH”", "Translate “HATCH”",
                        "—", "Удалить"])
    }

    /// Без системных пунктов — без лишних разделителей.
    func testMenuWithoutSystemItems() throws {
        let controller = LiveTextController()
        controller.menuItems = { ([ClosureMenuItem("Копировать картинку") {}], [ClosureMenuItem("Удалить") {}]) }
        let coordinator = LiveTextImage.Coordinator(controller: controller)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = coordinator.overlayView(ImageAnalysisOverlayView(), updatedMenuFor: NSMenu(), for: event, at: .zero)
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "—" : $0.title }, ["Копировать картинку", "—", "Удалить"])
    }

    func testClosureMenuItemRunsHandler() {
        var ran = false
        let item = ClosureMenuItem("Закрепить", key: "s", modifiers: .command) { ran = true }
        XCTAssertEqual(item.keyEquivalent, "s")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        _ = (item.target as AnyObject?)?.perform(item.action)
        XCTAssertTrue(ran)
    }
}

/// Размер окна просмотра: строго в пропорциях картинки, противоположный край на месте.
final class ClipPreviewResizeTests: XCTestCase {
    private let start = NSRect(x: 100, y: 100, width: 400, height: 200 + 30) // картинка 2:1 и шапка
    private let screen = CGSize(width: 1600, height: 1000)

    private func resized(_ edges: PreviewEdges, _ dx: CGFloat, _ dy: CGFloat) -> NSRect {
        ClipPreviewWindow.resized(start, edges: edges, delta: CGSize(width: dx, height: dy), ratio: 2, header: 30, bounds: screen)
    }

    func testRightEdgeKeepsTopLeft() {
        let frame = resized(.right, 100, 0)
        XCTAssertEqual(frame.width, 500)
        XCTAssertEqual(frame.height, 250 + 30, "высота — по ширине")
        XCTAssertEqual(frame.minX, start.minX)
        XCTAssertEqual(frame.maxY, start.maxY, "верх на месте")
    }

    func testLeftEdgeKeepsRight() {
        let frame = resized(.left, 100, 0) // влево — меньше
        XCTAssertEqual(frame.width, 300)
        XCTAssertEqual(frame.maxX, start.maxX)
        XCTAssertEqual(frame.maxY, start.maxY)
    }

    func testTopEdgeKeepsBottom() {
        let frame = resized(.top, 0, 50) // вверх на 50 — картинка выше на 50, шире на 100
        XCTAssertEqual(frame.width, 500)
        XCTAssertEqual(frame.minY, start.minY, "низ на месте")
    }

    func testCornerFollowsStrongerDirection() {
        let frame = resized([.bottom, .right], 20, -80) // вниз сильнее: высота +80 → ширина +160
        XCTAssertEqual(frame.width, 560)
        XCTAssertEqual(frame.maxY, start.maxY)
        XCTAssertEqual(frame.minX, start.minX)
    }

    func testClampedToMinimumAndScreen() {
        XCTAssertEqual(resized(.right, -1000, 0).width, ClipPreviewWindow.minWidth)
        // по высоте экрана: (1000 - 30) × 2 = 1940 > ширины экрана — упор в ширину
        XCTAssertEqual(resized(.right, 5000, 0).width, 1600)
        let tall = ClipPreviewWindow.resized(start, edges: .right, delta: CGSize(width: 5000, height: 0), ratio: 0.5,
                                             header: 30, bounds: screen)
        XCTAssertEqual(tall.height, 1000, "высокая картинка — упор в высоту экрана")
    }

    func testGripZones() {
        let size = CGSize(width: 400, height: 230)
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 200, y: 100), in: size), [], "внутри — картинка")
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 398, y: 100), in: size), [], "край между углами — нет")
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 200, y: 228), in: size), [])
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 398, y: 220), in: size), [.right, .bottom], "угол")
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 376, y: 225), in: size), [.right, .bottom], "вдоль нижнего края у угла")
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 380, y: 210), in: size), [], "внутри уголка — картинка")
        XCTAssertEqual(PreviewResizeView.edges(at: NSPoint(x: 2, y: 2), in: size), [.left, .top])
    }
}
