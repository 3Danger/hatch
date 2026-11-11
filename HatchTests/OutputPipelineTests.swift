import XCTest
@testable import Hatch

final class OutputPipelineTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        ShellTestIsolation.apply()
    }

    private func run(_ stages: [String], input: String) async -> OutputPipeline.Result {
        await OutputPipeline.run(stages: stages, input: input,
                                 directory: FileManager.default.temporaryDirectory.path,
                                 shell: "/bin/zsh",
                                 environment: ProcessInfo.processInfo.environment)
    }

    func testGrepFiltersSavedOutput() async {
        let result = await run(["grep b"], input: "alpha\nbeta\ngamma\nbravo")
        XCTAssertEqual(result.output, "beta\nbravo")
        XCTAssertEqual(result.status, 0)
    }

    func testStagesChainLikePipe() async {
        let result = await run(["grep a", "sort -r", "head -2"], input: "b-a\na-a\nc-a\nzzz")
        XCTAssertEqual(result.output, "c-a\nb-a")
    }

    func testQuotingPreserved() async {
        let result = await run([#"grep "two words""#], input: "one\ntwo words here\nthree")
        XCTAssertEqual(result.output, "two words here")
    }

    /// Ошибка шага видна в выводе, а не теряется.
    func testErrorsAreShown() async {
        let result = await run(["no-such-command-xyz"], input: "x")
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("no-such-command-xyz"), result.output)
    }

    /// Шаг не может читать что-то кроме сохранённого вывода: без него — пустой вход, а не зависание.
    func testEmptyInputDoesNotHang() async {
        let result = await run(["cat"], input: "")
        XCTAssertEqual(result.output, "")
    }
}
