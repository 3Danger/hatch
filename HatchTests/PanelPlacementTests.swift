import XCTest
@testable import Hatch

final class PanelPlacementTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = NSSize(width: 720, height: 560)

    func testDefaultIsTopCenter() {
        let origin = PanelPlacement.origin(saved: nil, panelSize: size, visibleFrames: [screen], main: screen)
        XCTAssertEqual(origin, NSPoint(x: 360, y: 875 - 560 - 40))
    }

    /// Пользователь передвинул окно — показываем там же.
    func testSavedOriginIsUsedWhenOnScreen() {
        let saved = NSPoint(x: 100, y: 200)
        let origin = PanelPlacement.origin(saved: saved, panelSize: size, visibleFrames: [screen], main: screen)
        XCTAssertEqual(origin, saved)
    }

    /// Монитор, на котором стояло окно, отключили — возвращаемся к позиции по умолчанию.
    func testSavedOriginOffScreenFallsBackToDefault() {
        let saved = NSPoint(x: 3000, y: 200)
        let origin = PanelPlacement.origin(saved: saved, panelSize: size, visibleFrames: [screen], main: screen)
        XCTAssertEqual(origin, NSPoint(x: 360, y: 275))
    }
}
