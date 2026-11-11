import XCTest
import AppKit
@testable import Hatch

/// Полосы прокрутки в Hatch нет — и у терминала раскрытого блока тоже.
final class TerminalScrollerTests: XCTestCase {
    @MainActor func testTerminalScrollerHidden() {
        let view = SessionTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let scrollers = view.subviews.compactMap { $0 as? NSScroller }
        XCTAssertFalse(scrollers.isEmpty, "у SwiftTerm есть своя полоса — её и прячем")
        XCTAssertTrue(scrollers.allSatisfy(\.isHidden))
    }
}
