import XCTest
import SwiftUI
@testable import Hatch

/// Большой вывод в раскрытом блоке не должен перерисовываться по кругу, когда ничего не меняется.
final class RenderLoopTests: XCTestCase {

    private func bigOutput(lines: Int) -> (plain: String, ansi: String) {
        let plain = (1...lines).map { "├── folder-\($0)/file-\($0).txt" }
        let ansi = plain.map { "\u{1B}[0;1;34m├──\u{1B}[0m \($0.dropFirst(4))" }
        return (plain.joined(separator: "\n"), ansi.joined(separator: "\n"))
    }

    func testExpandedBigOutputSettles() {
        let store = SessionStore(history: HistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("render-\(UUID().uuidString).json")))
        let output = bigOutput(lines: 1680)
        var big = Session(command: "tree -L 4", state: .completed, finishedAt: Date(), exitCode: 0)
        big.output = output.plain
        big.outputANSI = output.ansi
        store.add(Session(command: "ls", state: .completed, output: "a\nb", exitCode: 0))
        store.add(big)

        // как в панели: ширина фиксирована, высота окна — по содержимому
        let view = HistoryListView(lang: "ru", expandedID: big.id)
            .environment(store)
            .frame(width: 640)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        window.contentView = hosting
        window.orderFrontRegardless() // на экране: иначе SwiftUI не пересчитывает раскладку
        defer { window.orderOut(nil) }

        // первая отрисовка и замеры высот
        RenderProbe.reset()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        RenderProbe.reset()
        // ничего не меняется — перерисовок быть не должно
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        let renders = RenderProbe.counts["SessionBlockView"] ?? 0
        XCTAssertLessThanOrEqual(renders, 4, "блоки перерисовываются по кругу: \(renders) раз за секунду простоя")
    }
}
