import XCTest
@testable import Hatch

final class HistorySuggestionTests: XCTestCase {

    /// История от новых к старым.
    private let history = ["git status", "git push", "ls -la", "git status"]

    func testSuggestsMostRecentMatch() {
        XCTAssertEqual(HistorySuggestion.completion(for: "git", in: history), "git status")
        XCTAssertEqual(HistorySuggestion.completion(for: "git p", in: history), "git push")
    }

    func testNoSuggestionForExactOrUnknown() {
        XCTAssertNil(HistorySuggestion.completion(for: "ls -la", in: history), "уже набрано целиком")
        XCTAssertNil(HistorySuggestion.completion(for: "docker", in: history))
    }

    func testNoSuggestionForEmptyInput() {
        XCTAssertNil(HistorySuggestion.completion(for: "", in: history))
        XCTAssertNil(HistorySuggestion.completion(for: "   ", in: history))
    }

    /// Регистр учитывается, как в шелле: `Git` ≠ `git`.
    func testCaseSensitivePrefix() {
        XCTAssertNil(HistorySuggestion.completion(for: "GIT", in: history))
    }
}
