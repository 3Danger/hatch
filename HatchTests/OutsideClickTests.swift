import XCTest
import AppKit
@testable import Hatch

/// Клик по системному запросу разрешения — не клик мимо: панель не скрывается.
final class OutsideClickTests: XCTestCase {
    private func window(pid: pid_t, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid,
         kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: CGRect(x: x, y: y, width: width, height: height).dictionaryRepresentation]
    }

    /// Верхнее видимое окно в точке; координаты NSEvent (снизу) переводятся в координаты окон (сверху).
    func testTopVisibleWindowAtPoint() {
        let windows = [
            window(pid: 1, x: 0, y: 0, width: 100, height: 100, alpha: 0), // прозрачное — пропускаем
            window(pid: 2, x: 400, y: 300, width: 400, height: 200),        // запрос разрешения
            window(pid: 3, x: 0, y: 0, width: 1600, height: 1000),          // окно под ним
        ]
        // точка (500, 600) снизу при высоте экрана 1000 — это (500, 400) сверху: внутри запроса
        XCTAssertEqual(FloatingWindowController.windowOwner(at: NSPoint(x: 500, y: 600), windows: windows, primaryScreenHeight: 1000), 2)
        XCTAssertEqual(FloatingWindowController.windowOwner(at: NSPoint(x: 50, y: 950), windows: windows, primaryScreenHeight: 1000), 3)
        XCTAssertNil(FloatingWindowController.windowOwner(at: NSPoint(x: 5000, y: 5000), windows: windows, primaryScreenHeight: 1000))
    }

    /// Системные процессы, которые рисуют запросы разрешений, действительно есть в системе под этими id.
    func testSystemPromptAppsExist() {
        for id in ["com.apple.UserNotificationCenter", "com.apple.coreservices.uiagent", "com.apple.notificationcenterui"] {
            XCTAssertTrue(FloatingWindowController.systemPromptBundleIDs.contains(id))
            XCTAssertNotNil(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), id)
        }
        XCTAssertFalse(FloatingWindowController.systemPromptBundleIDs.contains("com.apple.finder"), "клик в Finder — мимо")
    }
}
