import XCTest
@testable import Hatch

final class ShellCompletionEngineTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        ShellTestIsolation.apply()
    }

    private var engine: ShellCompletionEngine { ShellCompletionEngine() }

    func testCommandSuggestionForEchoPrefix() {
        XCTAssertEqual(engine.suggestion(for: "ec"), "echo")
    }

    func testCommandSuggestionExactLs() {
        XCTAssertEqual(engine.suggestion(for: "ls"), "ls")
    }

    func testCommandNoMatchReturnsNil() {
        XCTAssertNil(engine.suggestion(for: "zzzznotacommand"))
    }

    func testEmptyBufferReturnsNil() {
        XCTAssertNil(engine.suggestion(for: "   "))
    }

    /// Относительные пути дополняются от текущей директории лаунчера.
    func testFileCompletionUsesWorkingDirectory() throws {
        let dir = try makeDir(files: ["alpha.txt"], dirs: ["alpine"])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        XCTAssertEqual(Set(engine.completions(for: "cat al")), ["alpha.txt", "alpine/"])
    }

    /// Для cd предлагаются только директории.
    func testCdCompletesOnlyDirectories() throws {
        let dir = try makeDir(files: ["alpha.txt"], dirs: ["alpine"])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        XCTAssertEqual(engine.completions(for: "cd al"), ["alpine/"])
    }

    // MARK: - Как в zsh: папки, содержимое, новое слово

    /// Имя папки дополняется косой чертой — следующий TAB покажет её содержимое.
    func testDirectoryGetsTrailingSlash() throws {
        let dir = try makeDir(files: [], dirs: ["Desktop"])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        XCTAssertEqual(engine.completions(for: "ls -la Desktop"), ["Desktop/"])
    }

    /// После косой черты — содержимое папки; набранный путь сохраняется как есть.
    func testContentsAfterSlash() throws {
        let dir = try makeDir(files: ["b.txt", ".hidden"], dirs: ["a"])
        let engine = ShellCompletionEngine()
        XCTAssertEqual(engine.completions(for: "ls \(dir.path)/"), ["\(dir.path)/a/", "\(dir.path)/b.txt"])
    }

    /// Скрытые — только если набрана точка.
    func testHiddenOnlyWithDot() throws {
        let dir = try makeDir(files: [".hidden", "visible"], dirs: [])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        XCTAssertEqual(engine.completions(for: "cat ."), [".hidden"])
    }

    /// `~` сохраняется в подсказке и раскрывается при поиске.
    func testTildeKeptInCandidates() {
        let engine = ShellCompletionEngine()
        XCTAssertTrue(engine.completions(for: "ls ~/").allSatisfy { $0.hasPrefix("~/") })
        XCTAssertEqual(engine.completions(for: "ls ~"), ["~/"])
    }

    /// Пробел в конце — начинается новое слово, предыдущее не заменяется.
    func testTrailingSpaceStartsNewWord() throws {
        let dir = try makeDir(files: ["only.txt"], dirs: [])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        XCTAssertEqual(engine.completions(for: "ls -la "), ["only.txt"])
        XCTAssertEqual(engine.applyCandidate("ls -la ", candidate: "only.txt"), "ls -la only.txt")
    }

    /// Набранное целиком имя файла дополнять нечем.
    func testExactFileNameGivesNothing() throws {
        let dir = try makeDir(files: ["done.txt"], dirs: [])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        XCTAssertEqual(engine.completions(for: "cat done.txt"), [])
    }

    /// Мгновенно: после прогрева ни одно нажатие не запускает шелл.
    func testCompletionIsFast() throws {
        let dir = try makeDir(files: (0..<300).map { "file\($0).txt" }, dirs: ["sub"])
        let engine = ShellCompletionEngine()
        engine.directory = dir.path
        _ = engine.completions(for: "ec")          // прогрев списка команд
        _ = engine.completions(for: "cat file")    // прогрев папки

        let start = Date()
        for text in ["e", "ec", "ech", "cat f", "cat file1", "cat file12", "ls su", "ls sub/"] {
            _ = engine.completions(for: text)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05, "8 нажатий дольше 50 мс")
    }

    private func makeDir(files: [String], dirs: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("comp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        files.forEach { FileManager.default.createFile(atPath: dir.appendingPathComponent($0).path, contents: nil) }
        try dirs.forEach {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent($0), withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testFileCompletionRelative() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("comp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("zeta.swift").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("zebra.txt").path, contents: nil)

        // файловый комплет идёт для 2-го+ токена (после команды)
        let buffer = "cat \(dir.appendingPathComponent("ze").path)"
        guard let suggestion = engine.suggestion(for: buffer) else {
            return XCTFail("ожидалась подсказка файла")
        }
        XCTAssertTrue(suggestion.contains("zebra.txt") || suggestion.contains("zeta.swift"))
    }

    func testCompletionLinePreservesLeadingTokens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("comp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("file1.txt").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("file2.log").path, contents: nil)

        let buffer = "cat \(dir.appendingPathComponent("file").path)"
        guard let line = engine.completionLine(for: buffer) else {
            return XCTFail("ожидалась строка подсказки")
        }
        XCTAssertTrue(line.hasPrefix("cat "))
        XCTAssertTrue(line.contains("file1.txt") || line.contains("file2.log"))
    }

    func testNormalizeHomePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(ShellCompletionEngine.normalizeHomePath(home), "~")
        XCTAssertEqual(ShellCompletionEngine.normalizeHomePath(home + "/Desktop"), "~/Desktop")
        XCTAssertEqual(ShellCompletionEngine.normalizeHomePath("/tmp/other"), "/tmp/other")
    }

    func testMultipleCandidates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("alpha.txt").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("alpine.log").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("banana.txt").path, contents: nil)

        let buffer = "cat \(dir.appendingPathComponent("al").path)"
        let comps = engine.completions(for: buffer)
        XCTAssertGreaterThanOrEqual(comps.count, 2)
        XCTAssertTrue(comps.contains { $0.hasSuffix("alpha.txt") })
        XCTAssertTrue(comps.contains { $0.hasSuffix("alpine.log") })
    }

    func testApplyCandidatePreservesCommand() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("apply-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let candidate = dir.appendingPathComponent("alpha.txt").path
        let buffer = "cat \(dir.appendingPathComponent("al").path)"

        let line = engine.applyCandidate(buffer, candidate: candidate)
        XCTAssertEqual(line, "cat \(candidate)")
    }
}
