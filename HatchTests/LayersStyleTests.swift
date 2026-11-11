import XCTest
@testable import Hatch

/// Стиль «Слои»: глубина блоков, статус, колпачки горячей клавиши, бегунок полосы прокрутки.
final class LayersStyleTests: XCTestCase {

    /// Все блоки на одной глубине: в покое чуть отодвинуты, наведённый выходит к 1, при раскрытом — в тени.
    func testBlocksRestAtOneDepth() {
        XCTAssertLessThan(LayersDepth.restingScale, 1)
        XCTAssertLessThan(LayersDepth.dimmedScale, LayersDepth.restingScale)
        XCTAssertLessThan(LayersDepth.restingOpacity, 1)
        XCTAssertLessThan(LayersDepth.dimmedOpacity, LayersDepth.restingOpacity)
    }

    /// Клик вне раскрытого блока сворачивает его; по самому блоку и по полосе прокрутки — нет.
    func testClickOutsideExpandedBlockCollapses() {
        let block = CGRect(x: 20, y: 100, width: 600, height: 300)
        let bar = CGRect(x: 630, y: 90, width: 14, height: 400)
        XCTAssertTrue(PanelFrames.collapses(at: CGPoint(x: 300, y: 50), expanded: block, scrollbar: bar))   // поле ввода
        XCTAssertTrue(PanelFrames.collapses(at: CGPoint(x: 300, y: 450), expanded: block, scrollbar: bar))  // блок ниже
        XCTAssertFalse(PanelFrames.collapses(at: CGPoint(x: 300, y: 200), expanded: block, scrollbar: bar)) // сам блок
        XCTAssertFalse(PanelFrames.collapses(at: CGPoint(x: 636, y: 300), expanded: block, scrollbar: bar)) // полоса
        XCTAssertFalse(PanelFrames.collapses(at: CGPoint(x: 300, y: 50), expanded: .null, scrollbar: bar))  // ничего не раскрыто
    }

    func testStatusFollowsSessionState() {
        var session = Session(command: "ls", state: .completed, exitCode: 0)
        XCTAssertEqual(BlockStatus(session), .done)
        session.exitCode = 2
        XCTAssertEqual(BlockStatus(session), .failed(2))
        session.state = .running
        XCTAssertEqual(BlockStatus(session), .running)
        XCTAssertTrue(BlockStatus(session).isActive)
        session.state = .stopped
        XCTAssertEqual(BlockStatus(session), .stopped)
        session.state = .interrupted
        XCTAssertEqual(BlockStatus(session), .interrupted)
        XCTAssertEqual(BlockStatus(Session(command: "x", state: .completed)), .done) // кода ещё нет
    }

    func testHotKeyCaps() {
        XCTAssertEqual(HotKeyCaps.keys(for: "alt-space"), ["⌥", "Space"])
        XCTAssertEqual(HotKeyCaps.keys(for: "ctrl-cmd-shift-k"), ["⌃", "⌘", "⇧", "K"])
        XCTAssertEqual(HotKeyCaps.keys(for: "cmd-return"), ["⌘", "↩"])
    }

    func testThumbFollowsScroll() {
        // список в 4 раза длиннее видимой части: бегунок — четверть дорожки
        let top = ScrollMetrics.thumb(offset: 0, content: 1600, visible: 400, track: 400)
        XCTAssertEqual(top.height, 100)
        XCTAssertEqual(top.y, 0)
        let bottom = ScrollMetrics.thumb(offset: 1200, content: 1600, visible: 400, track: 400)
        XCTAssertEqual(bottom.y, 300)
        // очень длинный список — бегунок не меньше, чем за него можно взяться
        XCTAssertEqual(ScrollMetrics.thumb(offset: 0, content: 100_000, visible: 400, track: 400).height, 28)
    }

    func testDraggingThumbScrollsProportionally() {
        // бегунок 100 на дорожке 400: сдвиг на 150 — половина пути, половина прокрутки
        XCTAssertEqual(ScrollMetrics.offset(dragging: 150, from: 0, content: 1600, visible: 400, track: 400), 600)
        // не дальше краёв
        XCTAssertEqual(ScrollMetrics.offset(dragging: 9999, from: 0, content: 1600, visible: 400, track: 400), 1200)
        XCTAssertEqual(ScrollMetrics.offset(dragging: -50, from: 100, content: 1600, visible: 400, track: 400), 0)
    }
}
