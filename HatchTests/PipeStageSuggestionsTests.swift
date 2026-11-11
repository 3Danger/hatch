import XCTest
@testable import Hatch

final class PipeStageSuggestionsTests: XCTestCase {

    /// Пустое поле: свои недавние шаги, затем частые фильтры, без повторов.
    func testEmptyInputOffersHistoryThenCommonFilters() {
        let list = PipeStageSuggestions.candidates(for: "", history: ["grep -v DEBUG", "sort"], completions: [])
        XCTAssertEqual(Array(list.prefix(2)), ["grep -v DEBUG", "sort"])
        XCTAssertTrue(list.contains("wc -l"))
        XCTAssertEqual(list.filter { $0 == "sort" }.count, 1)
    }

    /// По началу набранного: история первой, затем фильтры, затем дополнения шелла.
    func testPrefixMatchesOrderedBySource() {
        let list = PipeStageSuggestions.candidates(for: "gr", history: ["grep -v DEBUG", "sort"],
                                                   completions: ["grep", "groups"])
        XCTAssertEqual(list, ["grep -v DEBUG", "grep", "groups"])
    }

    func testCompletionsForArgumentsKeepFullLine() {
        let list = PipeStageSuggestions.candidates(for: "grep -f no", history: [],
                                                   completions: ["grep -f notes.txt"])
        XCTAssertEqual(list, ["grep -f notes.txt"])
    }

    func testLimit() {
        let many = (0..<50).map { "cmd\($0)" }
        XCTAssertLessThanOrEqual(PipeStageSuggestions.candidates(for: "cmd", history: many, completions: []).count,
                                 PipeStageSuggestions.limit)
    }
}
