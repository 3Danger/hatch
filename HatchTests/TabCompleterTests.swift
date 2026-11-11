import XCTest
@testable import Hatch

final class TabCompleterTests: XCTestCase {

    /// Подстановка последнего слова, как в ShellCompletionEngine.applyCandidate.
    private func apply(_ text: String, _ candidate: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        if words.isEmpty || text.hasSuffix(" ") { words.append("") }
        words[words.count - 1] = candidate
        return words.joined(separator: " ")
    }

    func testSingleCandidateApplied() {
        var tab = TabCompleter()
        XCTAssertEqual(tab.press(.forward, text: "ls ~/Des", candidates: ["~/Desktop/"], apply: apply), "ls ~/Desktop/")
        XCTAssertNil(tab.menu, "единственный вариант — без перебора")
    }

    /// Несколько вариантов: первый TAB дописывает только общую часть.
    func testFirstPressCompletesCommonPrefix() {
        var tab = TabCompleter()
        let text = tab.press(.forward, text: "ls ~/De", candidates: ["~/Desktop/", "~/Developer/"], apply: apply)
        XCTAssertEqual(text, "ls ~/De", "общая часть уже набрана — только показать список")
        XCTAssertNotNil(tab.menu)
        XCTAssertNil(tab.menu?.index, "ничего не вставлено до следующего TAB")

        var tab2 = TabCompleter()
        XCTAssertEqual(tab2.press(.forward, text: "cat al", candidates: ["alpha.txt", "alpine.log"], apply: apply),
                       "cat alp")
        XCTAssertNil(tab2.menu)
    }

    /// Дальше TAB перебирает варианты по кругу, не уходя вглубь.
    func testRepeatedPressCyclesVariants() {
        var tab = TabCompleter()
        let candidates = ["~/Desktop/", "~/Developer/", "~/Downloads/"]
        XCTAssertEqual(tab.press(.forward, text: "ls ~/D", candidates: candidates, apply: apply), "ls ~/D")
        XCTAssertEqual(tab.press(.forward, text: "ls ~/D", candidates: [], apply: apply), "ls ~/Desktop/")
        XCTAssertEqual(tab.press(.forward, text: "ls ~/Desktop/", candidates: [], apply: apply), "ls ~/Developer/")
        XCTAssertEqual(tab.press(.forward, text: "ls ~/Developer/", candidates: [], apply: apply), "ls ~/Downloads/")
        XCTAssertEqual(tab.press(.forward, text: "ls ~/Downloads/", candidates: [], apply: apply), "ls ~/Desktop/")
        XCTAssertEqual(tab.menu?.index, 0)
    }

    func testShiftTabGoesBack() {
        var tab = TabCompleter()
        let candidates = ["~/Desktop/", "~/Developer/", "~/Downloads/"]
        XCTAssertEqual(tab.press(.backward, text: "ls ~/D", candidates: candidates, apply: apply), "ls ~/D")
        XCTAssertEqual(tab.press(.backward, text: "", candidates: [], apply: apply), "ls ~/Downloads/")
        XCTAssertEqual(tab.press(.backward, text: "", candidates: [], apply: apply), "ls ~/Developer/")
    }

    /// Esc возвращает набранное до перебора.
    func testCancelRestoresTypedText() {
        var tab = TabCompleter()
        _ = tab.press(.forward, text: "ls ~/D", candidates: ["~/Desktop/", "~/Downloads/"], apply: apply)
        _ = tab.press(.forward, text: "ls ~/D", candidates: [], apply: apply)
        XCTAssertEqual(tab.cancel(), "ls ~/D")
        XCTAssertNil(tab.menu)
        XCTAssertNil(tab.cancel(), "вне перебора отменять нечего")
    }

    func testNoCandidates() {
        var tab = TabCompleter()
        XCTAssertNil(tab.press(.forward, text: "zzz", candidates: [], apply: apply))
    }

    func testCommonPrefix() {
        XCTAssertEqual(TabCompleter.commonPrefix(["alpha", "alpine", "alps"]), "alp")
        XCTAssertEqual(TabCompleter.commonPrefix(["привет", "приём"]), "при")
        XCTAssertEqual(TabCompleter.commonPrefix(["a", "b"]), "")
    }
}
